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

pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
imoprt {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


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


    /// \\\\\\\\\\\\\\\\\
    // State Variables //
    /// \\\\\\\\\\\\\\\\\
    uint256 private constant ADDITONAL_FEED_PRECISION = 1e10; // 10 decimals
    uint256 private constant PRECISION = 1e18; // 10 decimals

    mapping(address token => address priceFeed) private s_priceFeeds; //token to prcie feed mapping
    mapping(adress user => mapping(address token => uint256 amount)) private s_collateralDeposited; // user to token to amount mapping
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; //user to amount mapping
    address[] private s_collateralTokens; // array of all tokens accepted as collateral


    DecentralizedStableCoin private immutable i_dsc;

    // Events //
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    /// \\\\\\\\\\\\\\\\\
    //    Modifiers //
    /// \\\\\\\\\\\\\\\\
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token){
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine__NotAllowedToken();        
        _;}
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
        if(tokenAddresses.length != priceFeedAddress.length){
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
        }
        // For example ETH/USD, BTC/USD, MKR/USD, etc. 
        for (uint256 i = 0; i<tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }



    ///\\\\\\\\\\\\\\\\\\\\
    // External Fuctions //
    ///\\\\\\\\\\\\\\\\\\\\

    function depositCollateralAndMintDsc() external payable{}

    /**
     * @notice follows CEI pattern (Check, Effects, Interactions)
     * @param tokenCollateralAddress The address of the tokens to be deposited as collateral
     * @param amountCollateral The amount of collateral to be deposited 
     * @notice they must have more collateral value than the minimum threshold
     */

    function depoistCollarteral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) 
        external 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral; 
        emit CollateralDepositied(msg.sender, tokenCollateralAddress, amountCollateral);
        IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success){
            revert DSCEngine__TransferFailed();        
        }

    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // Mint 1. check if the collateral value > DSC amount. Need pricefeeds, values, etc. 
    // amountDscToMint lets user specify how much DSC they want to mint. Collateral = $200ETH => mint $20 DSC
    function mintDsc(uint256 amountDscToMint)  external moreThanZero(amountDscToMint) nonreentrant {
            s_dscMinted[msg.sender] += amountDscToMint;
            // if they minted too much(ex: minted $150DSC, but only have $100 worth of collateral), then revert
            revertIfHealthFactorIsBroken(msg.sender);

    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\   
    // Private and Internal View Fuctions //
    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

    function _getAccountInformation(address user) 
        private 
        view 
        returns(uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    } 

    // function _healthFactor returns how close a user is to liquidation.  Ratio of 1 means they are at the liquidation threshold.
        // use "_" before function names to let us know it's internal function
    function _healthFactor(address user) private view returns (uint256){
        // to figure out health factor, we need to know:
            //1. the value of all collateral
            //2. the value of all DSC minted by this user
        (uint256 collateralValue, uint256 dscValue) = _getAccountInformation(user);
    }

    function _revertIfHealthFactorisBroken(address user) internal view {
        //1. check health factor (do they have enough collateral?)
        //2. if not, revert
    }


    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\   
    // Public and External View Fuctions //
    ///\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

    function getAccountCollateralValue(address user) public view returns (uint256){
        // To get the total value of all collateral we need to:
            //1. loop through each collateral token
            //2. get the amount deposited
            //3. Map the token to the price feed
        for(uint256 i = 0; i<s_collateralTokens.length; i++)
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd +=

    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256){
        //1. get price feed address
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //2. get price feed value
        (,uint256 price,,,) = priceFeed.latestRoundData();
        //3. multiply amount by price feed value
            //3.1. convert ETH price and amount from wei. if 1ETH=$1000, chainlink will return price =(1000*1e8[max decimals])
            //...and amount is given in wei =(amount*1e18)
        return ((uint256(price) * ADDITONAL_FEED_PRECISION) * amount) / PRECISION;
        
    }


}