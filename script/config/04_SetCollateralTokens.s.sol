// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ConfigJsonRepo } from "@hmx-script/utils/ConfigJsonRepo.s.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { PLPv2 } from "@hmx/contracts/PLPv2.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IPyth } from "lib/pyth-sdk-solidity/IPyth.sol";
import { IOracleMiddleware } from "@hmx/oracles/interfaces/IOracleMiddleware.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";

contract SetCollateralTokens is ConfigJsonRepo {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    // collateralFactorBPS = 80%
    _addCollateralConfig(wethAssetId, 8000, true, address(0));
    // collateralFactorBPS = 80%
    _addCollateralConfig(wbtcAssetId, 8000, true, address(0));
    // collateralFactorBPS = 100%
    _addCollateralConfig(daiAssetId, 10000, true, address(0));
    // collateralFactorBPS = 100%
    _addCollateralConfig(usdcAssetId, 10000, true, address(0));
    // collateralFactorBPS = 100%
    _addCollateralConfig(usdtAssetId, 10000, true, address(0));
    // collateralFactorBPS = 80%
    _addCollateralConfig(glpAssetId, 8000, true, address(0));

    vm.stopBroadcast();
  }

  /// @notice to add collateral config with some default value
  /// @param _assetId Asset's ID
  /// @param _collateralFactorBPS token reliability factor to calculate buying power, 1e4 = 100%
  /// @param _isAccepted accepted to deposit as collateral
  /// @param _settleStrategy determine token will be settled for NON PLP collateral, e.g. aUSDC redeemed as USDC
  function _addCollateralConfig(
    bytes32 _assetId,
    uint32 _collateralFactorBPS,
    bool _isAccepted,
    address _settleStrategy
  ) private {
    IConfigStorage.CollateralTokenConfig memory _collatTokenConfig;
    IConfigStorage configStorage = IConfigStorage(getJsonAddress(".storages.config"));

    _collatTokenConfig.collateralFactorBPS = _collateralFactorBPS;
    _collatTokenConfig.accepted = _isAccepted;
    _collatTokenConfig.settleStrategy = _settleStrategy;

    configStorage.setCollateralTokenConfig(_assetId, _collatTokenConfig);
  }
}
