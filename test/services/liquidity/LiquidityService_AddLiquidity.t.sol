// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { console } from "forge-std/console.sol";

import { LiquidityService_Base } from "./LiquidityService_Base.t.sol";

import { LiquidityService } from "../../../src/services/LiquidityService.sol";
import { IConfigStorage } from "../../../src/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "../../../src/storages/interfaces/IPerpStorage.sol";

// LiquidityService_AddLiquidity - unit test for add liquidity function
// What is this test DONE
// - correctness
//   - add liquidity with dynamic fee
//   - add liquidity without dynamic fee
// - revert
//   - add liquidity on unlisted token
//   - add liquidity on not accepted token
//   - add liquidity with zero amount
//   - slippage check fail
//   - PLP transfer in cooldown period
contract LiquidityService_AddLiquidity is LiquidityService_Base {
  function setUp() public virtual override {
    super.setUp();
  }

  function testCorrectness_WhenPLPAddLiquidity_WithDynamicFee() external {}

  function testCorrectness_WhenPLPAddLiquidity_WithoutDynamicFee() external {}

  function testRevert_WhenPLPAddLiquidity_WithUnlistedToken() external {
    vm.expectRevert(abi.encodeWithSignature("LiquidityService_InvalidToken()"));
    // wbtc is not listed as plp token
    liquidityService.addLiquidity(ALICE, address(wbtc), 10 ether, 0);
  }

  function testRevert_WhenPLPAddLiquidity_WithNotAcceptedToken() external {
    // update weth to not accepted
    IConfigStorage.PLPTokenConfig memory _plpTokenConfig = configStorage
      .getPLPTokenConfig(address(weth));
    _plpTokenConfig.accepted = false;
    configStorage.setPlpTokenConfig(address(weth), _plpTokenConfig);

    vm.expectRevert(abi.encodeWithSignature("LiquidityService_InvalidToken()"));
    liquidityService.addLiquidity(ALICE, address(weth), 10 ether, 0);
  }

  function testRevert_WhenPLPAddLiquidity_WithZeroAmount() external {
    vm.expectRevert(abi.encodeWithSignature("LiquidityService_BadAmount()"));
    liquidityService.addLiquidity(ALICE, address(weth), 0, 0);
  }

  function testRevert_WhenPLPAddLiquidity_AndSlippageCheckFail() external {}

  function testRevert_WhenPLPTransferToken_AfterAddLiquidity_InCoolDownPeriod()
    external
  {}
}
