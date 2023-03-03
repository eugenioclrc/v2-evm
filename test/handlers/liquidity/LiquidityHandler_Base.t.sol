// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseTest } from "../../base/BaseTest.sol";
import { Deployer } from "../../base/Deployer.sol";

import { BaseTest, IPerpStorage, IConfigStorage } from "../../base/BaseTest.sol";

import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";

contract LiquidityHandler_Base is BaseTest {
  ILiquidityHandler liquidityHandler;

  function setUp() public virtual {
    liquidityHandler = deployLiquidityHandler(address(mockLiquidityService), address(mockPyth), 5 ether);
  }
}
