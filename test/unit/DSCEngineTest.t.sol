// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;//dsc engine
    HelperConfig config;
    address ethUsdPriceFee;
    address weth;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFee, weth, , , ) = config.activeNetworkConfig();
    }


/* \\\\\\\\\\\\\\\\\
\\ Price Tests \\\\\
\\\\\\\\\\\\\\\\\\*/

function testGetUsdValue() public {
    uint256 ethAmount = 15e18;//15 ETH
    //15e18 * $2000/eth = $30,000e18
    uint256 expectedUsd = 30000e18;
    uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
    assertEq(expectedUsd, actualUsd);
}




}