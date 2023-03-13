// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ConfigJsonRepo } from "@hmx-script/utils/ConfigJsonRepo.s.sol";

import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";

contract SetConfigStorage is ConfigJsonRepo {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    IConfigStorage configStorage = IConfigStorage(getJsonAddress(".storages.config"));
    address calculatorAddress = getJsonAddress(".calculator");
    address feeCalculatorAddress = getJsonAddress(".feeCalculator");
    address plpAddress = getJsonAddress(".tokens.plp");
    address wethAddress = getJsonAddress(".tokens.weth");
    address oracleMiddlewareAddress = getJsonAddress(".oracle.middleware");

    configStorage.setCalculator(calculatorAddress);
    configStorage.setFeeCalculator(feeCalculatorAddress);
    configStorage.setPLP(plpAddress);
    configStorage.setOracle(oracleMiddlewareAddress);
    configStorage.setWeth(wethAddress);

    vm.stopBroadcast();
  }
}
