// // SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

// pragma solidity 0.8.18;

// import { ConfigJsonRepo } from "@hmx-script/foundry/utils/ConfigJsonRepo.s.sol";
// import { ILiquidityHandler } from "@hmx/handlers/interfaces/ILiquidityHandler.sol";
// import { console } from "forge-std/console.sol";

// contract CreateAddLiquidityOrder is ConfigJsonRepo {
//   function run() public {
//     uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//     vm.startBroadcast(deployerPrivateKey);

//     ILiquidityHandler liquidityHandler = ILiquidityHandler(getJsonAddress(".handlers.liquidity"));
//     uint256 executionFee = liquidityHandler.executionOrderFee();
//     liquidityHandler.createAddLiquidityOrder{ value: executionFee }(
//       getJsonAddress(".tokens.usdc"),
//       1 * 1e6,
//       0,
//       executionFee,
//       false
//     );

//     vm.stopBroadcast();
//   }
// }
