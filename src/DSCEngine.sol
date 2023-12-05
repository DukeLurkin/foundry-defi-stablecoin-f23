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

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

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



contract DSCEngine {
    // Errors //
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();

    // State Variables //
    mapping(address token => address priceFeed) private s_priceFeeds; //token to prcie feed mapping

    DecentralizedStableCoin private immutable i_dsc;

    // Modifiers //
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    //modifier isAllowedToken(address token){_;}

    // Functions //
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
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }



    // External Functions //
    function depositCollateralAndMintDsc() external payable{}

    /**
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of collateral to deposit     * 
     */

    function depoistCollarteral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) {



    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc()  external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    





}