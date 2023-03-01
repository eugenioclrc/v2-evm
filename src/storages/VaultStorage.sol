// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IVaultStorage } from "./interfaces/IVaultStorage.sol";

/// @title VaultStorage
/// @notice storage contract to do accounting for token, and also hold physical tokens
contract VaultStorage is IVaultStorage {
  using Address for address;
  using SafeERC20 for IERC20;

  // EVENTs
  event LogSetTraderBalance(address indexed trader, address token, uint balance);

  uint256 public plpTotalLiquidityUSDE30;

  mapping(address => uint256) public totalAmount; //token => tokenAmount
  mapping(address => uint256) public plpLiquidityUSDE30; //token => PLPValueInUSD
  mapping(address => uint256) public plpLiquidity; // token => PLPTokenAmount
  mapping(address => uint256) public fees; // fee in token unit

  uint256 public plpLiquidityDebtUSDE30; // USD dept acccounting when tradingFee is not enough to repay to trader
  // token => tradingFee
  mapping(address => uint256) public marginFee; // sum of realized borrowing and funding fee when traders are settement their fees

  mapping(address => uint256) public devFees;

  // liquidity provider address => token => amount
  mapping(address => mapping(address => uint256)) public liquidityProviderBalances;
  mapping(address => address[]) public liquidityProviderTokens;

  // trader address (with sub-account) => token => amount
  mapping(address => mapping(address => uint256)) public traderBalances;
  // mapping(address => address[]) public traderTokens;
  mapping(address => address[]) public traderTokens;
  // mapping(token => strategy)
  mapping(address => address) public strategyOf;

  // @todo - modifier?
  function addFee(address _token, uint256 _amount) external {
    fees[_token] += _amount;
  }

  function addDevFee(address _token, uint256 _amount) external {
    devFees[_token] += _amount;
  }

  // @todo - modifier?
  function addPLPLiquidityUSDE30(address _token, uint256 _amount) external {
    plpLiquidityUSDE30[_token] += _amount;
  }

  function addMarginFee(address _token, uint256 _amount) external {
    marginFee[_token] += _amount;
  }

  function removeMarginFee(address _token, uint256 _amount) external {
    marginFee[_token] -= _amount;
  }

  function addPlpLiquidityDebtUSDE30(uint256 _value) external {
    plpTotalLiquidityUSDE30 += _value;
  }

  function removePlpLiquidityDebtUSDE30(uint256 _value) external {
    plpTotalLiquidityUSDE30 -= _value;
  }

  // @todo - modifier?
  function addPLPTotalLiquidityUSDE30(uint256 _liquidity) external {
    plpTotalLiquidityUSDE30 += _liquidity;
  }

  // @todo - modifier?
  function addPLPLiquidity(address _token, uint256 _amount) external {
    plpLiquidity[_token] += _amount;
  }

  /**
   * ERC20 interaction functions
   */
  function pullToken(address _token) external returns (uint256) {
    uint256 prevBalance = totalAmount[_token];
    uint256 nextBalance = IERC20(_token).balanceOf(address(this));

    totalAmount[_token] = nextBalance;

    return nextBalance - prevBalance;
  }

  function pushToken(address _token, address _to, uint256 _amount) external {
    IERC20(_token).safeTransfer(_to, _amount);
    totalAmount[_token] = IERC20(_token).balanceOf(address(this));
  }

  // @todo - modifier?
  function withdrawFee(address _token, uint256 _amount, address _receiver) external {
    if (_receiver == address(0)) revert IVaultStorage_ZeroAddress();
    // @todo only governance
    fees[_token] -= _amount;
    IERC20(_token).safeTransfer(_receiver, _amount);
  }

  // @todo - modifier?
  function removePLPLiquidityUSDE30(address _token, uint256 _value) external {
    // Underflow check
    if (plpLiquidityUSDE30[_token] <= _value) {
      plpLiquidityUSDE30[_token] = 0;
      return;
    }
    plpLiquidityUSDE30[_token] -= _value;
  }

  // @todo - modifier?
  function removePLPTotalLiquidityUSDE30(uint256 _value) external {
    // Underflow check
    if (plpTotalLiquidityUSDE30 <= _value) {
      plpTotalLiquidityUSDE30 = 0;
      return;
    }
    plpTotalLiquidityUSDE30 -= _value;
  }

  // @todo - modifier?
  function removePLPLiquidity(address _token, uint256 _amount) external {
    plpLiquidity[_token] -= _amount;
  }

  /**
   * VALIDATION
   */

  function validatAddTraderToken(address _trader, address _token) public view {
    address[] storage traderToken = traderTokens[_trader];

    for (uint256 i; i < traderToken.length; ) {
      if (traderToken[i] == _token) revert IVaultStorage_TraderTokenAlreadyExists();
      unchecked {
        i++;
      }
    }
  }

  function validateRemoveTraderToken(address _trader, address _token) public view {
    if (traderBalances[_trader][_token] != 0) revert IVaultStorage_TraderBalanceRemaining();
  }

  /**
   * GETTER
   */

  function getTraderTokens(address _subAccount) external view returns (address[] memory) {
    return traderTokens[_subAccount];
  }

  /**
   * SETTER
   */

  function setTraderBalance(address _trader, address _token, uint256 _balance) external {
    traderBalances[_trader][_token] = _balance;
    emit LogSetTraderBalance(_trader, _token, _balance);
  }

  function addTraderToken(address _trader, address _token) external {
    validatAddTraderToken(_trader, _token);
    traderTokens[_trader].push(_token);
  }

  function removeTraderToken(address _trader, address _token) external {
    validateRemoveTraderToken(_trader, _token);

    address[] storage traderToken = traderTokens[_trader];
    uint256 tokenLen = traderToken.length;
    uint256 lastTokenIndex = tokenLen - 1;

    // find and deregister the token
    for (uint256 i; i < tokenLen; ) {
      if (traderToken[i] == _token) {
        // delete the token by replacing it with the last one and then pop it from there
        if (i != lastTokenIndex) {
          traderToken[i] = traderToken[lastTokenIndex];
        }
        traderToken.pop();
        break;
      }

      unchecked {
        i++;
      }
    }
  }

  /**
   * Strategy
   */
  function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
    // If the _res length is less than 68, then the transaction failed silently (without a revert message)
    if (_returnData.length < 68) return "Transaction reverted silently";
    assembly {
      // Slice the sighash.
      _returnData := add(_returnData, 0x04)
    }
    return abi.decode(_returnData, (string)); // All that remains is the revert string
  }

  function cook(address _target, address _token, bytes calldata _callData) external returns (bytes memory) {
    // Check
    // 1. Only strategy for specific token can call this function
    if (strategyOf[_token] != msg.sender) revert IVaultStorage_Forbidden();
    // 2. Target must be a contract. This to prevent strategy calling to EOA.
    if (!_target.isContract()) revert IVaultStorage_TargetNotContract();

    // 3. Execute the call as what the strategy wants
    (bool _success, bytes memory _returnData) = _target.call(_callData);
    // 4. Revert if not success
    require(_success, _getRevertMsg(_returnData));

    return _returnData;
  }

  /**
   * CALCULATION
   */
  // @todo - add only whitelisted services
  function transferToken(address _subAccount, address _token, uint256 _amount) external {
    IERC20(_token).safeTransfer(_subAccount, _amount);
  }

  function pullPLPLiquidity(address _token) external view returns (uint256) {
    return IERC20(_token).balanceOf(address(this)) - plpLiquidity[_token];
  }

  /// @notice increase sub-account collateral
  /// @param _subAccount - sub account
  /// @param _token - collateral token to increase
  /// @param _amount - amount to increase
  function increaseTraderBalance(address _subAccount, address _token, uint256 _amount) external {
    traderBalances[_subAccount][_token] += _amount;
  }

  /// @notice decrease sub-account collateral
  /// @param _subAccount - sub account
  /// @param _token - collateral token to increase
  /// @param _amount - amount to increase
  function decreaseTraderBalance(address _subAccount, address _token, uint256 _amount) external {
    traderBalances[_subAccount][_token] -= _amount;
  }
}
