// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// base
import { Owned } from "@hmx/base/Owned.sol";

//contracts
import { OracleMiddleware } from "@hmx/oracle/OracleMiddleware.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { PerpStorage } from "@hmx/storages/PerpStorage.sol";

// Interfaces
import { ICalculator } from "./interfaces/ICalculator.sol";

contract Calculator is Owned, ICalculator {
  uint32 internal constant BPS = 1e4;
  uint64 internal constant ETH_PRECISION = 1e18;
  uint64 internal constant RATE_PRECISION = 1e18;

  // EVENTS
  event LogSetOracle(address indexed oldOracle, address indexed newOracle);
  event LogSetVaultStorage(address indexed oldVaultStorage, address indexed vaultStorage);
  event LogSetConfigStorage(address indexed oldConfigStorage, address indexed configStorage);
  event LogSetPerpStorage(address indexed oldPerpStorage, address indexed perpStorage);

  // STATES
  // @todo - move oracle config to storage
  address public oracle;
  address public vaultStorage;
  address public configStorage;
  address public perpStorage;

  constructor(address _oracle, address _vaultStorage, address _perpStorage, address _configStorage) {
    // Sanity check
    if (
      _oracle == address(0) || _vaultStorage == address(0) || _perpStorage == address(0) || _configStorage == address(0)
    ) revert ICalculator_InvalidAddress();

    PerpStorage(_perpStorage).getGlobalState();
    VaultStorage(_vaultStorage).plpLiquidityDebtUSDE30();
    ConfigStorage(_configStorage).getLiquidityConfig();

    oracle = _oracle;
    vaultStorage = _vaultStorage;
    configStorage = _configStorage;
    perpStorage = _perpStorage;
  }

  /// @notice getAUM in E30
  /// @param _isMaxPrice Use Max or Min Price
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return PLP Value in E18 format
  function getAUME30(bool _isMaxPrice, uint256 _limitPriceE30, bytes32 _limitAssetId) public view returns (uint256) {
    // @todo -  pendingBorrowingFeeE30
    // plpAUM = value of all asset + pnlShort + pnlLong + pendingBorrowingFee
    uint256 pendingBorrowingFeeE30 = 0;
    int256 pnlE30 = _getGlobalPNLE30();
    uint256 aum = _getPLPValueE30(_isMaxPrice, _limitPriceE30, _limitAssetId) + pendingBorrowingFeeE30;
    if (pnlE30 < 0) {
      aum += uint256(-pnlE30);
    } else {
      uint256 _pnl = uint256(pnlE30);
      if (aum < _pnl) return 0;
      unchecked {
        aum -= _pnl;
      }
    }

    return aum;
  }

  /// @notice getAUM
  /// @param _isMaxPrice Use Max or Min Price
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return PLP Value in E18 format
  function getAUM(bool _isMaxPrice, uint256 _limitPriceE30, bytes32 _limitAssetId) public view returns (uint256) {
    return getAUME30(_isMaxPrice, _limitPriceE30, _limitAssetId) / 1e12;
  }

  /// @notice GetPLPValue in E30
  /// @param _isMaxPrice Use Max or Min Price
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return PLP Value
  function getPLPValueE30(
    bool _isMaxPrice,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) external view returns (uint256) {
    return _getPLPValueE30(_isMaxPrice, _limitPriceE30, _limitAssetId);
  }

  /// @notice GetPLPValue in E30
  /// @param _isMaxPrice Use Max or Min Price
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return PLP Value
  function _getPLPValueE30(
    bool _isMaxPrice,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) internal view returns (uint256) {
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    bytes32[] memory _plpAssetIds = _configStorage.getPlpAssetIds();
    uint256 assetValue = 0;
    uint256 _len = _plpAssetIds.length;

    for (uint256 i = 0; i < _len; ) {
      uint256 value = _getPLPUnderlyingAssetValueE30(
        _plpAssetIds[i],
        _configStorage,
        _isMaxPrice,
        _limitPriceE30,
        _limitAssetId
      );

      unchecked {
        assetValue += value;
        ++i;
      }
    }

    return assetValue;
  }

  /// @notice Get PLP underlying asset value in E30
  /// @param _underlyingAssetId the underlying asset id, the one we want to find the value
  /// @param _configStorage config storage
  /// @param _isMaxPrice Use Max or Min Price
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return PLP Value
  function _getPLPUnderlyingAssetValueE30(
    bytes32 _underlyingAssetId,
    ConfigStorage _configStorage,
    bool _isMaxPrice,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) internal view returns (uint256) {
    ConfigStorage.AssetConfig memory _assetConfig = _configStorage.getAssetConfig(_underlyingAssetId);

    uint256 _priceE30;
    if (_limitPriceE30 > 0 && _limitAssetId == _underlyingAssetId) {
      _priceE30 = _limitPriceE30;
    } else {
      (_priceE30, , ) = OracleMiddleware(oracle).unsafeGetLatestPrice(_underlyingAssetId, _isMaxPrice);
    }
    uint256 value = (VaultStorage(vaultStorage).plpLiquidity(_assetConfig.tokenAddress) * _priceE30) /
      (10 ** _assetConfig.decimals);

    return value;
  }

  /// @notice getPLPPrice in e18 format
  /// @param _aum aum in PLP
  /// @param _plpSupply Total Supply of PLP token
  /// @return PLP Price in e18
  function getPLPPrice(uint256 _aum, uint256 _plpSupply) public pure returns (uint256) {
    if (_plpSupply == 0) return 0;
    return _aum / _plpSupply;
  }

  /// @notice get all PNL in e30 format
  /// @return pnl value
  function _getGlobalPNLE30() internal view returns (int256) {
    // SLOAD
    ConfigStorage _configStorage = ConfigStorage(configStorage);
    PerpStorage _perpStorage = PerpStorage(perpStorage);
    OracleMiddleware _oracle = OracleMiddleware(oracle);

    int256 totalPnlLong = 0;
    int256 totalPnlShort = 0;
    uint256 _len = _configStorage.getMarketConfigsLength();

    for (uint256 i = 0; i < _len; ) {
      ConfigStorage.MarketConfig memory _marketConfig = _configStorage.getMarketConfigByIndex(i);
      PerpStorage.GlobalMarket memory _globalMarket = _perpStorage.getGlobalMarketByIndex(i);

      int256 _pnlLongE30 = 0;
      int256 _pnlShortE30 = 0;

      (uint256 priceE30Long, , ) = _oracle.unsafeGetLatestPrice(_marketConfig.assetId, false);
      (uint256 priceE30Short, , ) = _oracle.unsafeGetLatestPrice(_marketConfig.assetId, true);

      if (_globalMarket.longAvgPrice > 0 && _globalMarket.longPositionSize > 0) {
        if (priceE30Long < _globalMarket.longAvgPrice) {
          uint256 _absPNL = ((_globalMarket.longAvgPrice - priceE30Long) * _globalMarket.longPositionSize) /
            _globalMarket.longAvgPrice;
          _pnlLongE30 = -int256(_absPNL);
        } else {
          uint256 _absPNL = ((priceE30Long - _globalMarket.longAvgPrice) * _globalMarket.longPositionSize) /
            _globalMarket.longAvgPrice;
          _pnlLongE30 = int256(_absPNL);
        }
      }

      if (_globalMarket.shortAvgPrice > 0 && _globalMarket.shortPositionSize > 0) {
        if (_globalMarket.shortAvgPrice < priceE30Short) {
          uint256 _absPNL = ((priceE30Short - _globalMarket.shortAvgPrice) * _globalMarket.shortPositionSize) /
            _globalMarket.shortAvgPrice;

          _pnlShortE30 = -int256(_absPNL);
        } else {
          uint256 _absPNL = ((_globalMarket.shortAvgPrice - priceE30Short) * _globalMarket.shortPositionSize) /
            _globalMarket.shortAvgPrice;
          _pnlShortE30 = int256(_absPNL);
        }
      }

      {
        unchecked {
          i++;
          totalPnlLong += _pnlLongE30;
          totalPnlShort += _pnlShortE30;
        }
      }
    }

    return totalPnlLong + totalPnlShort;
  }

  /// @notice getMintAmount in e18 format
  /// @param _aum aum in PLP
  /// @param _totalSupply PLP total supply
  /// @param _value value in USD e30
  /// @return mintAmount in e18 format
  function getMintAmount(uint256 _aum, uint256 _totalSupply, uint256 _value) public pure returns (uint256) {
    return _aum == 0 ? _value / 1e12 : (_value * _totalSupply) / _aum / 1e12;
  }

  function convertTokenDecimals(
    uint256 fromTokenDecimals,
    uint256 toTokenDecimals,
    uint256 amount
  ) public pure returns (uint256) {
    return (amount * 10 ** toTokenDecimals) / 10 ** fromTokenDecimals;
  }

  function getAddLiquidityFeeRate(
    address _token,
    uint256 _tokenValueE30,
    ConfigStorage _configStorage
  ) external view returns (uint256) {
    if (!_configStorage.getLiquidityConfig().dynamicFeeEnabled) {
      return _configStorage.getLiquidityConfig().depositFeeRateBPS;
    }

    return
      _getFeeRate(
        _tokenValueE30,
        _getPLPUnderlyingAssetValueE30(_configStorage.tokenAssetIds(_token), _configStorage, false, 0, 0),
        _getPLPValueE30(false, 0, 0),
        _configStorage.getLiquidityConfig(),
        _configStorage.getAssetPlpTokenConfigByToken(_token),
        LiquidityDirection.ADD
      );
  }

  function getRemoveLiquidityFeeRate(
    address _token,
    uint256 _tokenValueE30,
    ConfigStorage _configStorage
  ) external view returns (uint256) {
    if (!_configStorage.getLiquidityConfig().dynamicFeeEnabled) {
      return _configStorage.getLiquidityConfig().withdrawFeeRateBPS;
    }

    return
      _getFeeRate(
        _tokenValueE30,
        _getPLPUnderlyingAssetValueE30(_configStorage.tokenAssetIds(_token), _configStorage, true, 0, 0),
        _getPLPValueE30(true, 0, 0),
        _configStorage.getLiquidityConfig(),
        _configStorage.getAssetPlpTokenConfigByToken(_token),
        LiquidityDirection.REMOVE
      );
  }

  function _getFeeRate(
    uint256 _value,
    uint256 _liquidityUSD, //e30
    uint256 _totalLiquidityUSD, //e30
    ConfigStorage.LiquidityConfig memory _liquidityConfig,
    ConfigStorage.PLPTokenConfig memory _plpTokenConfig,
    LiquidityDirection direction
  ) internal pure returns (uint32) {
    uint32 _feeRateBPS = direction == LiquidityDirection.ADD
      ? _liquidityConfig.depositFeeRateBPS
      : _liquidityConfig.withdrawFeeRateBPS;
    uint32 _taxRateBPS = _liquidityConfig.taxFeeRateBPS;
    uint256 _totalTokenWeight = _liquidityConfig.plpTotalTokenWeight;

    uint256 startValue = _liquidityUSD;
    uint256 nextValue = startValue + _value;
    if (direction == LiquidityDirection.REMOVE) nextValue = _value > startValue ? 0 : startValue - _value;

    uint256 targetValue = _getTargetValue(_totalLiquidityUSD, _plpTokenConfig.targetWeight, _totalTokenWeight);
    if (targetValue == 0) return _feeRateBPS;

    uint256 startTargetDiff = startValue > targetValue ? startValue - targetValue : targetValue - startValue;

    uint256 nextTargetDiff = nextValue > targetValue ? nextValue - targetValue : targetValue - nextValue;

    // nextValue moves closer to the targetValue -> positive case;
    // Should apply rebate.
    if (nextTargetDiff < startTargetDiff) {
      uint32 rebateRateBPS = uint32((_taxRateBPS * startTargetDiff) / targetValue);
      return rebateRateBPS > _feeRateBPS ? 0 : _feeRateBPS - rebateRateBPS;
    }

    // _nextWeight represented 18 precision
    uint256 _nextWeight = (nextValue * ETH_PRECISION) / targetValue;
    // if weight exceed targetWeight(e18) + maxWeight(e18)
    if (_nextWeight > _plpTokenConfig.targetWeight + _plpTokenConfig.maxWeightDiff) {
      revert ICalculator_PoolImbalance();
    }

    // If not then -> negative impact to the pool.
    // Should apply tax.
    uint256 midDiff = (startTargetDiff + nextTargetDiff) / 2;
    if (midDiff > targetValue) {
      midDiff = targetValue;
    }
    _taxRateBPS = uint32((_taxRateBPS * midDiff) / targetValue);

    return _feeRateBPS + _taxRateBPS;
  }

  /// @notice get settlement fee rate
  /// @param _token - token
  /// @param _liquidityUsdDelta - withdrawal amount
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _settlementFeeRate in e18 format
  function getSettlementFeeRate(
    address _token,
    uint256 _liquidityUsdDelta,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) external view returns (uint256 _settlementFeeRate) {
    // usd debt
    uint256 _tokenLiquidityUsd = _getPLPUnderlyingAssetValueE30(
      ConfigStorage(configStorage).tokenAssetIds(_token),
      ConfigStorage(configStorage),
      false,
      _limitPriceE30,
      _limitAssetId
    );
    if (_tokenLiquidityUsd == 0) return 0;

    // total usd debt

    uint256 _totalLiquidityUsd = _getPLPValueE30(false, _limitPriceE30, _limitAssetId);
    ConfigStorage.LiquidityConfig memory _liquidityConfig = ConfigStorage(configStorage).getLiquidityConfig();

    // target value = total usd debt * target weight ratio (targe weigh / total weight);
    uint256 _targetUsd = (_totalLiquidityUsd *
      ConfigStorage(configStorage).getAssetPlpTokenConfigByToken(_token).targetWeight) /
      _liquidityConfig.plpTotalTokenWeight;

    if (_targetUsd == 0) return 0;

    // next value
    uint256 _nextUsd = _tokenLiquidityUsd - _liquidityUsdDelta;

    // current target diff
    uint256 _currentTargetDiff;
    uint256 _nextTargetDiff;
    unchecked {
      _currentTargetDiff = _tokenLiquidityUsd > _targetUsd
        ? _tokenLiquidityUsd - _targetUsd
        : _targetUsd - _tokenLiquidityUsd;
      // next target diff
      _nextTargetDiff = _nextUsd > _targetUsd ? _nextUsd - _targetUsd : _targetUsd - _nextUsd;
    }

    if (_nextTargetDiff < _currentTargetDiff) return 0;

    // settlement fee rate = (next target diff + current target diff / 2) * base tax fee / target usd
    return
      (((_nextTargetDiff + _currentTargetDiff) / 2) * _liquidityConfig.taxFeeRateBPS * ETH_PRECISION) /
      _targetUsd /
      BPS;
  }

  // return in e18
  function _getTargetValue(
    uint256 totalLiquidityUSD, //e18
    uint256 tokenWeight,
    uint256 totalTokenWeight
  ) public pure returns (uint256) {
    if (totalLiquidityUSD == 0) return 0;

    return (totalLiquidityUSD * tokenWeight) / totalTokenWeight;
  }

  ////////////////////////////////////////////////////////////////////////////////////
  //////////////////////  SETTERs  ///////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////

  /// @notice Set new Oracle contract address.
  /// @param _oracle New Oracle contract address.
  function setOracle(address _oracle) external onlyOwner {
    // @todo - Sanity check
    if (_oracle == address(0)) revert ICalculator_InvalidAddress();
    emit LogSetOracle(oracle, _oracle);
    oracle = _oracle;
  }

  /// @notice Set new VaultStorage contract address.
  /// @param _vaultStorage New VaultStorage contract address.
  function setVaultStorage(address _vaultStorage) external onlyOwner {
    // @todo - Sanity check
    if (_vaultStorage == address(0)) revert ICalculator_InvalidAddress();
    emit LogSetVaultStorage(vaultStorage, _vaultStorage);
    vaultStorage = _vaultStorage;
  }

  /// @notice Set new ConfigStorage contract address.
  /// @param _configStorage New ConfigStorage contract address.
  function setConfigStorage(address _configStorage) external onlyOwner {
    // @todo - Sanity check
    if (_configStorage == address(0)) revert ICalculator_InvalidAddress();
    emit LogSetConfigStorage(configStorage, _configStorage);
    configStorage = _configStorage;
  }

  /// @notice Set new PerpStorage contract address.
  /// @param _perpStorage New PerpStorage contract address.
  function setPerpStorage(address _perpStorage) external onlyOwner {
    // @todo - Sanity check
    if (_perpStorage == address(0)) revert ICalculator_InvalidAddress();
    emit LogSetPerpStorage(perpStorage, _perpStorage);
    perpStorage = _perpStorage;
  }

  ////////////////////////////////////////////////////////////////////////////////////
  ////////////////////// CALCULATOR
  ////////////////////////////////////////////////////////////////////////////////////

  /// @notice Calculate for value on trader's account including Equity, IMR and MMR.
  /// @dev Equity = Sum(collateral tokens' Values) + Sum(unrealized PnL) - Unrealized Borrowing Fee - Unrealized Funding Fee
  /// @param _subAccount Trader account's address.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _equityValueE30 Total equity of trader's account.
  function getEquity(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) public view returns (int256 _equityValueE30) {
    // Calculate collateral tokens' value on trader's sub account
    uint256 _collateralValueE30 = getCollateralValue(_subAccount, _limitPriceE30, _limitAssetId);

    // Calculate unrealized PnL on opening trader's position(s)
    int256 _unrealizedPnlValueE30 = getUnrealizedPnl(_subAccount, _limitPriceE30, _limitAssetId);

    // Calculate Borrowing fee on opening trader's position(s)
    // @todo - calculate borrowing fee
    // uint256 borrowingFeeE30 = getBorrowingFee(_subAccount);

    // @todo - calculate funding fee
    // uint256 fundingFeeE30 = getFundingFee(_subAccount);

    // Sum all asset's values
    _equityValueE30 += int256(_collateralValueE30);
    _equityValueE30 += _unrealizedPnlValueE30;

    // @todo - include borrowing and funding fee
    // _equityValueE30 -= borrowingFeeE30;
    // _equityValueE30 -= fundingFeeE30;

    return _equityValueE30;
  }

  // @todo integrate realizedPnl Value

  /// @notice Calculate unrealized PnL from trader's sub account.
  /// @dev This unrealized pnl deducted by collateral factor.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _unrealizedPnlE30 PnL value after deducted by collateral factor.
  function getUnrealizedPnl(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) public view returns (int256 _unrealizedPnlE30) {
    // Get all trader's opening positions
    PerpStorage.Position[] memory _traderPositions = PerpStorage(perpStorage).getPositionBySubAccount(_subAccount);

    // Loop through all trader's positions
    for (uint256 i; i < _traderPositions.length; ) {
      PerpStorage.Position memory _position = _traderPositions[i];
      bool _isLong = _position.positionSizeE30 > 0 ? true : false;

      if (_position.avgEntryPriceE30 == 0) revert ICalculator_InvalidAveragePrice();

      // Get market config according to opening position
      ConfigStorage.MarketConfig memory _marketConfig = ConfigStorage(configStorage).getMarketConfigByIndex(
        _position.marketIndex
      );

      // Long position always use MinPrice. Short position always use MaxPrice
      bool _isUseMaxPrice = _isLong ? false : true;

      // Check to overwrite price
      uint256 _priceE30;
      if (_limitAssetId == _marketConfig.assetId && _limitPriceE30 != 0) {
        _priceE30 = _limitPriceE30;
      } else {
        // Get price from oracle
        // @todo - validate price age
        (_priceE30, , ) = OracleMiddleware(oracle).getLatestPriceWithMarketStatus(
          _marketConfig.assetId,
          _isUseMaxPrice
        );
      }
      // Calculate for priceDelta
      uint256 _priceDeltaE30;
      unchecked {
        _priceDeltaE30 = _position.avgEntryPriceE30 > _priceE30
          ? _position.avgEntryPriceE30 - _priceE30
          : _priceE30 - _position.avgEntryPriceE30;
      }

      int256 _delta = (_position.positionSizeE30 * int(_priceDeltaE30)) / int(_position.avgEntryPriceE30);

      if (_isLong) {
        _delta = _priceE30 > _position.avgEntryPriceE30 ? _delta : -_delta;
      } else {
        _delta = _priceE30 < _position.avgEntryPriceE30 ? -_delta : _delta;
      }

      // If profit then deduct PnL with collateral factor.
      _delta = _delta > 0 ? (int32(ConfigStorage(configStorage).pnlFactorBPS()) * _delta) / int32(BPS) : _delta;

      // Accumulative current unrealized PnL
      _unrealizedPnlE30 += _delta;

      unchecked {
        i++;
      }
    }

    return _unrealizedPnlE30;
  }

  /// @notice Calculate collateral tokens to value from trader's sub account.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _collateralValueE30
  function getCollateralValue(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) public view returns (uint256 _collateralValueE30) {
    // Get list of current depositing tokens on trader's account
    address[] memory _traderTokens = VaultStorage(vaultStorage).getTraderTokens(_subAccount);

    // Loop through list of current depositing tokens
    for (uint256 i; i < _traderTokens.length; ) {
      address _token = _traderTokens[i];
      ConfigStorage.CollateralTokenConfig memory _collateralTokenConfig = ConfigStorage(configStorage)
        .getCollateralTokenConfigs(_token);

      // Get token decimals from ConfigStorage
      uint256 _decimals = ConfigStorage(configStorage).getAssetConfigByToken(_token).decimals;

      // Get collateralFactor from ConfigStorage
      uint32 collateralFactorBPS = _collateralTokenConfig.collateralFactorBPS;

      // Get current collateral token balance of trader's account
      uint256 _amount = VaultStorage(vaultStorage).traderBalances(_subAccount, _token);

      // Get price from oracle
      uint256 _priceE30;

      // Get token asset id from ConfigStorage
      bytes32 _tokenAssetId = ConfigStorage(configStorage).tokenAssetIds(_token);
      if (_tokenAssetId == _limitAssetId && _limitPriceE30 != 0) {
        _priceE30 = _limitPriceE30;
      } else {
        // @todo - validate price age
        (_priceE30, , ) = OracleMiddleware(oracle).getLatestPriceWithMarketStatus(
          _tokenAssetId,
          false // @note Collateral value always use Min price
        );
      }
      // Calculate accumulative value of collateral tokens
      // collateral value = (collateral amount * price) * collateralFactorBPS
      // collateralFactor 1e4 = 100%
      _collateralValueE30 += (_amount * _priceE30 * collateralFactorBPS) / ((10 ** _decimals) * BPS);

      unchecked {
        i++;
      }
    }

    return _collateralValueE30;
  }

  /// @notice Calculate Initial Margin Requirement from trader's sub account.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @return _imrValueE30 Total imr of trader's account.
  function getIMR(address _subAccount) public view returns (uint256 _imrValueE30) {
    // Get all trader's opening positions
    PerpStorage.Position[] memory _traderPositions = PerpStorage(perpStorage).getPositionBySubAccount(_subAccount);

    // Loop through all trader's positions
    for (uint256 i; i < _traderPositions.length; ) {
      PerpStorage.Position memory _position = _traderPositions[i];

      uint256 _size;
      if (_position.positionSizeE30 < 0) {
        _size = uint(_position.positionSizeE30 * -1);
      } else {
        _size = uint(_position.positionSizeE30);
      }

      // Calculate IMR on position
      _imrValueE30 += calculatePositionIMR(_size, _position.marketIndex);

      unchecked {
        i++;
      }
    }

    return _imrValueE30;
  }

  /// @notice Calculate Maintenance Margin Value from trader's sub account.
  /// @param _subAccount Trader's address that combined between Primary account and Sub account.
  /// @return _mmrValueE30 Total mmr of trader's account
  function getMMR(address _subAccount) public view returns (uint256 _mmrValueE30) {
    // Get all trader's opening positions
    PerpStorage.Position[] memory _traderPositions = PerpStorage(perpStorage).getPositionBySubAccount(_subAccount);

    // Loop through all trader's positions
    for (uint256 i; i < _traderPositions.length; ) {
      PerpStorage.Position memory _position = _traderPositions[i];

      uint256 _size;
      if (_position.positionSizeE30 < 0) {
        _size = uint(_position.positionSizeE30 * -1);
      } else {
        _size = uint(_position.positionSizeE30);
      }
      // Calculate MMR on position
      _mmrValueE30 += calculatePositionMMR(_size, _position.marketIndex);

      unchecked {
        i++;
      }
    }

    return _mmrValueE30;
  }

  /// @notice Calculate for Initial Margin Requirement from position size.
  /// @param _positionSizeE30 Size of position.
  /// @param _marketIndex Market Index from opening position.
  /// @return _imrE30 The IMR amount required on position size, 30 decimals.
  function calculatePositionIMR(uint256 _positionSizeE30, uint256 _marketIndex) public view returns (uint256 _imrE30) {
    // Get market config according to position
    ConfigStorage.MarketConfig memory _marketConfig = ConfigStorage(configStorage).getMarketConfigByIndex(_marketIndex);

    _imrE30 = (_positionSizeE30 * _marketConfig.initialMarginFractionBPS) / BPS;
    return _imrE30;
  }

  /// @notice Calculate for Maintenance Margin Requirement from position size.
  /// @param _positionSizeE30 Size of position.
  /// @param _marketIndex Market Index from opening position.
  /// @return _mmrE30 The MMR amount required on position size, 30 decimals.
  function calculatePositionMMR(uint256 _positionSizeE30, uint256 _marketIndex) public view returns (uint256 _mmrE30) {
    // Get market config according to position
    ConfigStorage.MarketConfig memory _marketConfig = ConfigStorage(configStorage).getMarketConfigByIndex(_marketIndex);

    _mmrE30 = (_positionSizeE30 * _marketConfig.maintenanceMarginFractionBPS) / BPS;
    return _mmrE30;
  }

  /// @notice This function returns the amount of free collateral available to a given sub-account
  /// @param _subAccount The address of the sub-account
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _freeCollateral The amount of free collateral available to the sub-account
  function getFreeCollateral(
    address _subAccount,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) public view returns (uint256 _freeCollateral) {
    int256 equity = getEquity(_subAccount, _limitPriceE30, _limitAssetId);
    uint256 imr = getIMR(_subAccount);

    if (equity < int256(imr)) return 0;
    _freeCollateral = uint256(equity) - imr;
    return _freeCollateral;
  }

  /// @notice get next short average price with realized PNL
  /// @param _market - global market
  /// @param _currentPrice - min / max price depends on position direction
  /// @param _positionSizeDelta - position size after increase / decrease.
  ///                           if positive is LONG position, else is SHORT
  /// @param _realizedPositionPnl - position realized PnL if positive is profit, and negative is loss
  /// @return _nextAveragePrice next average price
  function calculateShortAveragePrice(
    PerpStorage.GlobalMarket memory _market,
    uint256 _currentPrice,
    int256 _positionSizeDelta,
    int256 _realizedPositionPnl
  ) external pure returns (uint256 _nextAveragePrice) {
    // global
    uint256 _globalPositionSize = _market.shortPositionSize;
    int256 _globalAveragePrice = int256(_market.shortAvgPrice);

    if (_globalAveragePrice == 0) return 0;

    // if positive means, has profit
    int256 _globalPnl = (int256(_globalPositionSize) * (_globalAveragePrice - int256(_currentPrice))) /
      _globalAveragePrice;
    int256 _newGlobalPnl = _globalPnl - _realizedPositionPnl;

    uint256 _newGlobalPositionSize;
    // position > 0 is means decrease short position
    // else is increase short position
    if (_positionSizeDelta > 0) {
      _newGlobalPositionSize = _globalPositionSize - uint256(_positionSizeDelta);
    } else {
      _newGlobalPositionSize = _globalPositionSize + uint256(-_positionSizeDelta);
    }

    bool _isGlobalProfit = _newGlobalPnl > 0;
    uint256 _absoluteGlobalPnl = uint256(_isGlobalProfit ? _newGlobalPnl : -_newGlobalPnl);

    // divisor = latest global position size - pnl
    uint256 divisor = _isGlobalProfit
      ? (_newGlobalPositionSize - _absoluteGlobalPnl)
      : (_newGlobalPositionSize + _absoluteGlobalPnl);

    if (divisor == 0) return 0;

    // next short average price = current price * latest global position size / latest global position size - pnl
    _nextAveragePrice = (_currentPrice * _newGlobalPositionSize) / divisor;

    return _nextAveragePrice;
  }

  /// @notice get next long average price with realized PNL
  /// @param _market - global market
  /// @param _currentPrice - min / max price depends on position direction
  /// @param _positionSizeDelta - position size after increase / decrease.
  ///                           if positive is LONG position, else is SHORT
  /// @param _realizedPositionPnl - position realized PnL if positive is profit, and negative is loss
  /// @return _nextAveragePrice next average price
  function calculateLongAveragePrice(
    PerpStorage.GlobalMarket memory _market,
    uint256 _currentPrice,
    int256 _positionSizeDelta,
    int256 _realizedPositionPnl
  ) external pure returns (uint256 _nextAveragePrice) {
    // global
    uint256 _globalPositionSize = _market.longPositionSize;
    int256 _globalAveragePrice = int256(_market.longAvgPrice);

    if (_globalAveragePrice == 0) return 0;

    // if positive means, has profit
    int256 _globalPnl = (int256(_globalPositionSize) * (int256(_currentPrice) - _globalAveragePrice)) /
      _globalAveragePrice;
    int256 _newGlobalPnl = _globalPnl - _realizedPositionPnl;

    uint256 _newGlobalPositionSize;
    // position > 0 is means increase short position
    // else is decrease short position
    if (_positionSizeDelta > 0) {
      _newGlobalPositionSize = _globalPositionSize + uint256(_positionSizeDelta);
    } else {
      _newGlobalPositionSize = _globalPositionSize - uint256(-_positionSizeDelta);
    }

    bool _isGlobalProfit = _newGlobalPnl > 0;
    uint256 _absoluteGlobalPnl = uint256(_isGlobalProfit ? _newGlobalPnl : -_newGlobalPnl);

    // divisor = latest global position size + pnl
    uint256 divisor = _isGlobalProfit
      ? (_newGlobalPositionSize + _absoluteGlobalPnl)
      : (_newGlobalPositionSize - _absoluteGlobalPnl);

    if (divisor == 0) return 0;

    // next long average price = current price * latest global position size / latest global position size + pnl
    _nextAveragePrice = (_currentPrice * _newGlobalPositionSize) / divisor;

    return _nextAveragePrice;
  }

  /// @notice Calculate next funding rate using when increase/decrease position.
  /// @param _marketIndex Market Index.
  /// @param _limitPriceE30 Price from limit order
  /// @return fundingRate next funding rate using for both LONG & SHORT positions.
  /// @return fundingRateLong next funding rate for LONG.
  /// @return fundingRateShort next funding rate for SHORT.
  function getNextFundingRate(
    uint256 _marketIndex,
    uint256 _limitPriceE30
  ) external view returns (int256 fundingRate, int256 fundingRateLong, int256 fundingRateShort) {
    ConfigStorage _configStorage = ConfigStorage(configStorage);
    GetFundingRateVar memory vars;
    ConfigStorage.MarketConfig memory marketConfig = ConfigStorage(configStorage).getMarketConfigByIndex(_marketIndex);
    PerpStorage.GlobalMarket memory globalMarket = PerpStorage(perpStorage).getGlobalMarketByIndex(_marketIndex);
    if (marketConfig.fundingRate.maxFundingRateBPS == 0 || marketConfig.fundingRate.maxSkewScaleUSD == 0)
      return (0, 0, 0);
    // Get funding interval
    vars.fundingInterval = _configStorage.getTradingConfig().fundingInterval;
    // If block.timestamp not pass the next funding time, return 0.
    if (globalMarket.lastFundingTime + vars.fundingInterval > block.timestamp) return (0, 0, 0);
    int32 _exponent;
    if (_limitPriceE30 != 0) {
      vars.marketPriceE30 = _limitPriceE30;
    } else {
      //@todo - validate timestamp of these
      (vars.marketPriceE30, _exponent, ) = OracleMiddleware(ConfigStorage(configStorage).oracle()).unsafeGetLatestPrice(
        marketConfig.assetId,
        false
      );
    }
    vars.marketSkewUSDE30 =
      ((int(globalMarket.longOpenInterest) - int(globalMarket.shortOpenInterest)) * int(vars.marketPriceE30)) /
      int(10 ** uint32(-_exponent));
    // The result of this nextFundingRate Formula will be in the range of [-maxFundingRateBPS, maxFundingRateBPS]
    vars.ratio = _max(-1e18, -((vars.marketSkewUSDE30 * 1e18) / int(marketConfig.fundingRate.maxSkewScaleUSD)));
    vars.ratio = _min(vars.ratio, 1e18);
    vars.nextFundingRate = (vars.ratio * int(uint(marketConfig.fundingRate.maxFundingRateBPS))) / 1e4;

    vars.elapsedIntervals = int((block.timestamp - globalMarket.lastFundingTime) / vars.fundingInterval);
    vars.newFundingRate = (globalMarket.currentFundingRate + vars.nextFundingRate) * vars.elapsedIntervals;

    if (globalMarket.longOpenInterest > 0) {
      fundingRateLong = (vars.newFundingRate * int(globalMarket.longPositionSize)) / 1e30;
    }
    if (globalMarket.shortOpenInterest > 0) {
      fundingRateShort = (vars.newFundingRate * -int(globalMarket.shortPositionSize)) / 1e30;
    }
    return (vars.newFundingRate, fundingRateLong, fundingRateShort);
  }

  /**
   * Funding Rate
   */
  /// @notice This function returns funding fee according to trader's position
  /// @param _marketIndex Index of market
  /// @param _isLong Is long or short exposure
  /// @param _size Position size
  /// @return fundingFee Funding fee of position
  function getFundingFee(
    uint256 _marketIndex,
    bool _isLong,
    int256 _size,
    int256 _entryFundingRate
  ) external view returns (int256 fundingFee) {
    if (_size == 0) return 0;
    uint256 absSize = _size > 0 ? uint(_size) : uint(-_size);

    PerpStorage.GlobalMarket memory _globalMarket = PerpStorage(perpStorage).getGlobalMarketByIndex(_marketIndex);

    int256 _fundingRate = _globalMarket.currentFundingRate - _entryFundingRate;

    // IF _fundingRate < 0, LONG positions pay fees to SHORT and SHORT positions receive fees from LONG
    // IF _fundingRate > 0, LONG positions receive fees from SHORT and SHORT pay fees to LONG
    fundingFee = (int256(absSize) * _fundingRate) / int64(RATE_PRECISION);

    // @todo - funding fee Bug found here, must be resolved
    if (_isLong) {
      return _fundingRate < 0 ? -fundingFee : fundingFee;
    } else {
      return _fundingRate < 0 ? -fundingFee : fundingFee;
    }
  }

  /// @notice Calculates the borrowing fee for a given asset class based on the reserved value, entry borrowing rate, and current sum borrowing rate of the asset class.
  /// @param _assetClassIndex The index of the asset class for which to calculate the borrowing fee.
  /// @param _reservedValue The reserved value of the asset class.
  /// @param _entryBorrowingRate The entry borrowing rate of the asset class.
  /// @return borrowingFee The calculated borrowing fee for the asset class.
  function getBorrowingFee(
    uint8 _assetClassIndex,
    uint256 _reservedValue,
    uint256 _entryBorrowingRate
  ) external view returns (uint256 borrowingFee) {
    // Get the global asset class.
    PerpStorage.GlobalAssetClass memory _globalAssetClass = PerpStorage(perpStorage).getGlobalAssetClassByIndex(
      _assetClassIndex
    );
    // Calculate borrowing rate.
    uint256 _borrowingRate = _globalAssetClass.sumBorrowingRate - _entryBorrowingRate;
    // Calculate the borrowing fee based on reserved value, borrowing rate.
    return (_reservedValue * _borrowingRate) / RATE_PRECISION;
  }

  /// @notice This function takes an asset class index as input and returns the next borrowing rate for that asset class.
  /// @param _assetClassIndex The index of the asset class.
  /// @param _limitPriceE30 Price to be overwritten to a specified asset
  /// @param _limitAssetId Asset to be overwritten by _limitPriceE30
  /// @return _nextBorrowingRate The next borrowing rate for the asset class.
  function getNextBorrowingRate(
    uint8 _assetClassIndex,
    uint256 _limitPriceE30,
    bytes32 _limitAssetId
  ) public view returns (uint256 _nextBorrowingRate) {
    ConfigStorage _configStorage = ConfigStorage(configStorage);

    // Get the trading config, asset class config, and global asset class for the given asset class index.
    ConfigStorage.TradingConfig memory _tradingConfig = _configStorage.getTradingConfig();
    ConfigStorage.AssetClassConfig memory _assetClassConfig = _configStorage.getAssetClassConfigByIndex(
      _assetClassIndex
    );
    PerpStorage.GlobalAssetClass memory _globalAssetClass = PerpStorage(perpStorage).getGlobalAssetClassByIndex(
      _assetClassIndex
    );
    // Get the PLP TVL.
    uint256 plpTVL = _getPLPValueE30(false, _limitPriceE30, _limitAssetId);

    // If block.timestamp not pass the next funding time, return 0.
    if (_globalAssetClass.lastBorrowingTime + _tradingConfig.fundingInterval > block.timestamp) return 0;
    // If PLP TVL is 0, return 0.
    if (plpTVL == 0) return 0;

    // Calculate the number of funding intervals that have passed since the last borrowing time.
    uint256 intervals = (block.timestamp - _globalAssetClass.lastBorrowingTime) / _tradingConfig.fundingInterval;

    // Calculate the next borrowing rate based on the asset class config, global asset class reserve value, and intervals.
    return
      (_assetClassConfig.baseBorrowingRateBPS * _globalAssetClass.reserveValueE30 * intervals * RATE_PRECISION) /
      plpTVL /
      BPS;
  }

  function _max(int256 a, int256 b) internal pure returns (int256) {
    return a > b ? a : b;
  }

  function _min(int256 a, int256 b) internal pure returns (int256) {
    return a < b ? a : b;
  }
}
