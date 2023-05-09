// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ConfigJsonRepo } from "@hmx-script/utils/ConfigJsonRepo.s.sol";

import { BotHandler } from "@hmx/handlers/BotHandler.sol";
import { CrossMarginHandler } from "@hmx/handlers/CrossMarginHandler.sol";
import { LimitTradeHandler } from "@hmx/handlers/LimitTradeHandler.sol";
import { LiquidityHandler } from "@hmx/handlers/LiquidityHandler.sol";
import { MarketTradeHandler } from "@hmx/handlers/MarketTradeHandler.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployHandlers is ConfigJsonRepo {
  struct ContractAddress {
    address pythAddress;
    address tradeServiceAddress;
    address liquidationServiceAddress;
    address liquidityServiceAddress;
    address crossMarginServiceAddress;
    address weth;
  }

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address proxyAdmin = getJsonAddress(".proxyAdmin");

    ContractAddress memory vars = ContractAddress(
      getJsonAddress(".oracles.pyth"),
      getJsonAddress(".services.trade"),
      getJsonAddress(".services.liquidation"),
      getJsonAddress(".services.liquidity"),
      getJsonAddress(".services.crossMargin"),
      getJsonAddress(".tokens.weth")
    );

    // @todo - TBD
    uint256 executionOrderFee = 0.0001 ether;

    address limitTradeHandlerAddress = address(
      Deployer.deployLimitTradeHandler(
        address(proxyAdmin),
        vars.weth,
        vars.tradeServiceAddress,
        vars.pythAddress,
        executionOrderFee
      )
    );

    vm.stopBroadcast();

    updateJson(".handlers.limitTrade", limitTradeHandlerAddress);
  }
}
