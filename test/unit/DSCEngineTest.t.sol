// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;//dsc engine
    HelperConfig public config;
    address ethUsdPriceFee;
    address weth;

    address public USER = makeAddr("user"); 
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;


    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFee, ,weth, , ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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
    console2.log("actual Usd: ", actualUsd);
}


/* \\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\\ Deposit Collateral Tests \\\\\
\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*/


function testRevertsIfCollateralZero() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dsce.depositCollateral(weth, 0);
    vm.stopPrank();

}



}