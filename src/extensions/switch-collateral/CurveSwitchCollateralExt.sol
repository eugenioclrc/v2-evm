// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

// bases
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { ISwitchCollateralExt } from "@hmx/extensions/switch-collateral/interfaces/ISwitchCollateralExt.sol";
import { IStableSwap } from "@hmx/interfaces/curve/IStableSwap.sol";
import { IWNative } from "@hmx/interfaces/IWNative.sol";

contract CurveSwitchCollateralExt is Ownable, ISwitchCollateralExt {
  using SafeERC20 for ERC20;

  error CurveSwitchCollateralExt_PoolNotSet();

  struct PoolConfig {
    IStableSwap pool;
    int128 fromIndex;
    int128 toIndex;
  }
  mapping(address => mapping(address => PoolConfig)) public poolOf;
  IWNative public immutable weth;
  address internal constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  event LogSetPoolConfig(
    address indexed tokenIn,
    address indexed tokenOut,
    address prevPool,
    int128 prevFromIndex,
    int128 prevToIndex,
    address pool,
    int128 fromIndex,
    int128 toIndex
  );

  constructor(address _weth) {
    weth = IWNative(_weth);
  }

  function run(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 /* _minAmountOut */,
    bytes calldata /* _data */
  ) external override returns (uint256 _amountOut) {
    // SLOAD
    PoolConfig memory _poolConfig = poolOf[_tokenIn][_tokenOut];

    // Check
    // If poolConfig not set, then revert
    if (address(_poolConfig.pool) == address(0)) revert CurveSwitchCollateralExt_PoolNotSet();

    // Approve tokenIn to pool if needed
    ERC20 _tIn = ERC20(_tokenIn);
    if (_tIn.allowance(address(this), address(_poolConfig.pool)) < _amountIn)
      _tIn.safeApprove(address(_poolConfig.pool), type(uint256).max);

    // Swap
    _amountOut = _poolConfig.pool.exchange(_poolConfig.fromIndex, _poolConfig.toIndex, _amountIn, 0);

    // If tokenOut is ETH, then wrap ETH
    if (_poolConfig.pool.coins(uint256(int256(_poolConfig.toIndex))) == CURVE_ETH) {
      weth.deposit{ value: _amountOut }();
    }

    // Transfer tokenOut to msg.sender
    ERC20(_tokenOut).safeTransfer(msg.sender, _amountOut);
  }

  /*
   * Setters
   */

  /// @notice Set pool config.
  /// @param _tokenIn Token to swap from.
  /// @param _tokenOut Token to swap to.
  /// @param _pool Curve pool address.
  /// @param _fromIndex Index of tokenIn in the pool.
  /// @param _toIndex Index of tokenOut in the pool.
  function setPoolConfig(
    address _tokenIn,
    address _tokenOut,
    address _pool,
    int128 _fromIndex,
    int128 _toIndex
  ) external onlyOwner {
    // SLOAD
    PoolConfig memory _prevPoolConfig = poolOf[_tokenIn][_tokenOut];
    emit LogSetPoolConfig(
      _tokenIn,
      _tokenOut,
      address(_prevPoolConfig.pool),
      _prevPoolConfig.fromIndex,
      _prevPoolConfig.toIndex,
      _pool,
      _fromIndex,
      _toIndex
    );
    poolOf[_tokenIn][_tokenOut] = PoolConfig({ pool: IStableSwap(_pool), fromIndex: _fromIndex, toIndex: _toIndex });
  }
}
