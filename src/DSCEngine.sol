// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Lukas Durkin
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stable coin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was onloy backed by WETH and WBTC.
 *
 * Our DSC system should ALWAYS be over collateralized.  At no point, should the value of all collateral <= value of all DSC.
 *
 * @notice This contract is the core of the DSC System.  It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system. It is not a fork, and is not intended to be a fork.  It is a completely different system.
 */

contract DSCEngine is ReentrancyGuard {
    /// \\\\\\\\\\
    //  Errors  //
    /// \\\\\\\\\\
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    /// \\\\\\\\\\\\\\\\\
    // State Variables //
    /// \\\\\\\\\\\\\\\\\
    uint256 private constant ADDITONAL_FEED_PRECISION = 1e10; // 10 decimals
    uint256 private constant PRECISION = 1e18; // 10 decimals
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // must be at least 200% overcollateralized
    uint256 private constant LIQUDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidating a user

    mapping(address token => address priceFeed) private s_priceFeeds; //token to prcie feed mapping
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited; // user to token to amount mapping
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted; //user to amount mapping
    address[] private s_collateralTokens; // array of all tokens accepted as collateral

    DecentralizedStableCoin private immutable i_dsc;

    /// \\\\\\\\\\\\
    //    Events  //
    /// \\\\\\\\\\\\
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    /// \\\\\\\\\\\\\\\\\
    //    Modifiers //
    /// \\\\\\\\\\\\\\\\
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /// \\\\\\\\\\\\\\\\
    //      Fuctions //
    /// \\\\\\\\\\\\\\\\
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        // USD price feeds
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
        }
        // For example ETH/USD, BTC/USD, MKR/USD, etc.
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///\\\\\\\\\\\\\\\\\\\\
    // External Fuctions //
    ///\\\\\\\\\\\\\\\\\\\\

    /*
     * @param tokenCollateralAddress The address of the tokens to be deposited as collateral
     * @param amountCollateral The amount of collateral to be deposited
     * @param amountDscToMint The amount of decentralized stable coin to be minted
     * @notice this function will deposit collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external payable {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern (Check, Effects, Interactions)
     * @param tokenCollateralAddress The address of the tokens to be deposited as collateral
     * @param amountCollateral The amount of collateral to be deposited
     * @notice they must have more collateral value than the minimum threshold
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param tokenCollateralAddress The collateral address to redeem
    * @param amountCollateral The amount of collateral to redeem
    * @param amountDscToBurn The amount of DSC to burn
    * This function burns DSC and redeems underlying collateral in one transaction
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external 
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // no need to revert if health factor is broken bc redeemCollateral already checks
    }

    //in order to redeem collateral:
    // 1. health factor must be over 1 AFTER collateral is removed
    // DRY: Don't Repeat Yourself
    // Follow CEI: Check, Effects, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
        public 
        moreThanZero(amountCollateral) 
        nonReentrant 
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //Redeeming is above, however, say we want to completely remove all DSC and eth from the protocol:
    // If we remove the ETH first then HealthFactor will be broken
    // So, step 1. burn DSC
    // Step 2. redeem ETH(collateral)

    // Mint 1. check if the collateral value > DSC amount. Need pricefeeds, values, etc.
    // amountDscToMint lets user specify how much DSC they want to mint. Collateral = $200ETH => mint $20 DSC
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much(ex: minted $150DSC, but only have $100 worth of collateral), then revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
        //probably don't need revert if health is broken bc removing dsc will increase health factor
    }

    //if we get near undercollaterization, we need to liquidate the user's collateral
    //if somoene is almost undercollateralized, the smart contract will pay a user to liquidate them. 
    //$75 backing $50 in DSC(under health factor) - user who liquidates "bad" user gets $75 worth of collateral for $50 worth of DSC(burned)
    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */

    //remember to follow CEI: Check, Effects, Interactions
    function liquidate(address collateral, address user, uint256 debtToCover) 
        external 
        moreThanZero(debtToCover)
        nonReentrant
    {//1. check health factor
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOK();
        } 
        _revertIfHealthFactorIsBroken(msg.sender);
    //next burn the DSC debt
    // take bad users collateral
    // ex: Bad user: $140ETH, $100 DSC
    // debtToCover = $100 ^^^
    // So need to know: $100 DSC = ???ETH
    // about 0.05 ETH
    uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
    //We are giving the liquidator $110(10% bounus) in WETH for $100 in DSC
    // We should implement a feature to liquidate in the event the protocol is insolvent
    // and put extra amounts into a treasury(NOT part of this project)

    // .05 * .1 = .005. Giving good user .055ETH (with 10% bonus)
    uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS)/LIQUDATION_PRECISION;
    uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
    _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
    // We need to burn the DSC
    _burnDsc(debtToCover, user, msg.sender);


    uint256 endingUserHealthFactor = _healthFactor(user);
    if (endingUserHealthFactor <= startingUserHealthFactor){
        revert DSCEngine__HealthFactorNotImproved();
    }
    }

    function getHealthFactor() external view {}

    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    // Private and Internal View Fuctions //
    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

    /**
     * @dev low-level internal function, do not call unles the function calling it is
     * checking for health factors being broken
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    // function _healthFactor returns how close a user is to liquidation.  Ratio of 1 means they are at the liquidation threshold.
    // use "_" before function names to let us know it's internal function
    function _healthFactor(address user) private view returns (uint256) {
        // to figure out health factor, we need to know:
        //1. the value of all collateral
        //2. the value of all DSC minted by this user
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //1. check health factor (do they have enough collateral?)
        //2. if not, revert
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    // Public and External View Fuctions //
    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){
        //price of ETH (token)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10)
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITONAL_FEED_PRECISION); 
    }


    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // To get the total value of all collateral we need to:
        //1. loop through each collateral token
        //2. get the amount deposited
        //3. Map the token to the price feed
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        //1. get price feed address
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        //2. get price feed value
        (, int256 price, , , ) = priceFeed.latestRoundData();
        //3. multiply amount by price feed value
        //3.1. convert ETH price and amount from wei. if 1ETH=$1000, chainlink will return price =(1000*1e8[max decimals])
        //...and amount is given in wei =(amount*1e18)
        return
            ((uint256(price) * ADDITONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user) external view returns
        (uint256 totalDscMinted, uint256 collateralValueInUsd) 
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }


}
