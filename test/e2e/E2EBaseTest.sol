// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { TestBase } from "forge-std/Base.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheatsSafe } from "forge-std/StdCheats.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

// import { MockErc20 } from "@hmx-test/mocks/MockErc20.sol";
// import { MockWNative } from "@hmx-test/mocks/MockWNative.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { MockPyth } from "pyth-sdk-solidity/MockPyth.sol";

import { IOracleMiddleware } from "@hmx/oracle/interfaces/IOracleMiddleware.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { IPLPv2 } from "@hmx/contracts/interfaces/IPLPv2.sol";

import { IBotHandler } from "@hmx/handlers/interfaces/IBotHandler.sol";
import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";
import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
import { IMarketTradeHandler } from "@hmx/handlers/interfaces/IMarketTradeHandler.sol";

import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";
import { ILiquidityService } from "@hmx/services/interfaces/ILiquidityService.sol";
import { ILiquidationService } from "@hmx/services/interfaces/ILiquidationService.sol";
import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";

abstract contract E2EBaseTest is TestBase, StdAssertions, StdCheatsSafe {
  address internal ALICE;
  address internal BOB;
  address internal CAROL;
  address internal DAVE;

  address internal PYTH_ADDRESS = address(0);

  /* CONTRACTS */
  IOracleMiddleware oracleMiddleWare;
  IConfigStorage configStorage;
  IPerpStorage perpStorage;
  IVaultStorage vaultStorage;
  ICalculator calculator;

  // handlers
  IBotHandler botHandler;
  ICrossMarginHandler crossMarginHandler;
  ILimitTradeHandler limitTradeHandler;
  ILiquidityHandler liquidityHandler;
  IMarketTradeHandler marketTradeHandler;

  // services
  ICrossMarginService crossMarginService;
  ILiquidityService liquidityService;
  ILiquidationService liquidationService;
  ITradeService tradService;

  /* TOKENS */

  //LP tokens
  ERC20 glp;
  IPLPv2 plpV2;

  // UNDERLYING ARBRITRUM GLP => ETH WBTC LINK UNI USDC USDT DAI FRAX
  ERC20 weth; //for native
  ERC20 wbtc; // decimals 8
  ERC20 usdc; // decimals 6
  ERC20 usdt; // decimals 6
  ERC20 dai; // decimals 18

  ERC20 gmx; //decimals 18

  address jpy = address(0);

  /* MARKET */

  // assetIds
  bytes32 internal constant wethAssetId = "weth";
  bytes32 internal constant wbtcAssetId = "wbtc";

  bytes32 internal constant gmxAssetId = "gmx";

  bytes32 internal constant jpyAssetId = "jpy";

  /* PYTH */
  IOracleAdapter internal pyth;

  constructor() {
    ALICE = makeAddr("Alice");
    BOB = makeAddr("BOB");
    CAROL = makeAddr("CAROL");
    DAVE = makeAddr("DAVE");

    // deploy pyth adapter
    IOracleAdapter oracleAdapter = Deployer.deployPythAdapter(PYTH_ADDRESS);
    // deploy stakedGLPOracleAdapter

    // deploy oracleMiddleWare
    oracleMiddleWare = Deployer.deployOracleMiddleware(address(oracleAdapter));

    // deploy configStorage
    configStorage = Deployer.deployConfigStorage();

    // deploy perpStorage
    perpStorage = Deployer.deployPerpStorage();

    // deploy vaultStorage
    vaultStorage = Deployer.deployVaultStorage();

    // deploy plp
    plpV2 = Deployer.deployPLPv2();

    // deploy calculator
    calculator = Deployer.deployCalculator(
      address(oracleMiddleWare),
      address(vaultStorage),
      address(perpStorage),
      address(configStorage)
    );

    // deploy handler and service
    liquidityService = Deployer.deployLiquidityService(
      address(perpStorage),
      address(vaultStorage),
      address(configStorage)
    );
    liquidationService = Deployer.deployLiquidationService(
      address(perpStorage),
      address(vaultStorage),
      address(configStorage)
    );
    crossMarginService = Deployer.deployCrossMarginService(
      address(configStorage),
      address(vaultStorage),
      address(calculator)
    );
    tradeService = Deployer.deployTradeService(address(perpStorage), address(vaultStorage), address(configStorage));

    botHandler = Deployer.deployBotHandler(address(tradeService), address(liquidationService), PYTH_ADDRESS);
    ICrossMarginHandler crossMarginHandler;
    ILimitTradeHandler limitTradeHandler;
    ILiquidityHandler liquidityHandler;
    IMarketTradeHandler marketTradeHandler;
    /* 
    import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";
import { ILiquidityService } from "@hmx/services/interfaces/ILiquidityService.sol";
import { ILiquidationService } from "@hmx/services/interfaces/ILiquidationService.sol";
import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";

     */
    /* configStorage */
    // serviceExecutor
    // calculator
    // oracle
    // plp
    // weth
  }
}
