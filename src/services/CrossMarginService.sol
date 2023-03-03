// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

//base
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Owned } from "@hmx/base/Owned.sol";

// contracts
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { Calculator } from "@hmx/contracts/Calculator.sol";

// Interfaces
import { ICrossMarginService } from "./interfaces/ICrossMarginService.sol";

contract CrossMarginService is Owned, ReentrancyGuard, ICrossMarginService {
  /**
   * Events
   */
  event LogSetConfigStorage(address indexed oldConfigStorage, address newConfigStorage);
  event LogSetVaultStorage(address indexed oldVaultStorage, address newVaultStorage);
  event LogSetCalculator(address indexed oldCalculator, address newCalculator);
  event LogDepositCollateral(address indexed primaryAccount, address indexed subAccount, address token, uint256 amount);
  event LogWithdrawCollateral(
    address indexed primaryAccount,
    address indexed subAccount,
    address token,
    uint256 amount
  );

  /**
   * States
   */
  address public configStorage;
  address public vaultStorage;
  address public calculator;

  constructor(address _configStorage, address _vaultStorage, address _calculator) {
    if (_configStorage == address(0) || _vaultStorage == address(0) || _calculator == address(0))
      revert ICrossMarginService_InvalidAddress();

    configStorage = _configStorage;
    vaultStorage = _vaultStorage;
    calculator = _calculator;

    // Sanity check
    ConfigStorage(_configStorage).calculator();
    VaultStorage(_vaultStorage).devFees(address(0));
    Calculator(_calculator).oracle();
  }

  /**
   * Modifiers
   */
  // NOTE: Validate only whitelisted contract be able to call this function
  modifier onlyWhitelistedExecutor() {
    ConfigStorage(configStorage).validateServiceExecutor(address(this), msg.sender);
    _;
  }

  // NOTE: Validate only accepted collateral token to be deposited
  modifier onlyAcceptedToken(address _token) {
    ConfigStorage(configStorage).validateAcceptedCollateral(_token);
    _;
  }

  /**
   * Core functions
   */
  /// @notice Calculate new trader balance after deposit collateral token.
  /// @dev This uses to calculate new trader balance when they deposit token as collateral.
  /// @param _primaryAccount Trader's primary address from trader's wallet.
  /// @param _subAccountId Trader's Sub-Account Id.
  /// @param _token Token that's deposited as collateral.
  /// @param _amount Token depositing amount.
  function depositCollateral(
    address _primaryAccount,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant onlyWhitelistedExecutor onlyAcceptedToken(_token) {
    address _vaultStorage = vaultStorage;

    // Get trader's sub-account address
    address _subAccount = _getSubAccount(_primaryAccount, _subAccountId);

    // Get current collateral token balance of trader's account
    // and sum with new token depositing amount
    uint256 _oldBalance = VaultStorage(_vaultStorage).traderBalances(_subAccount, _token);

    uint256 _newBalance = _oldBalance + _amount;

    // Set new collateral token balance
    VaultStorage(_vaultStorage).setTraderBalance(_subAccount, _token, _newBalance);

    // Update token balance
    uint256 deltaBalance = VaultStorage(_vaultStorage).pullToken(_token);
    if (deltaBalance < _amount) revert ICrossMarginService_InvalidDepositBalance();

    // If trader's account never contain this token before then register new token to the account
    if (_oldBalance == 0 && _newBalance != 0) {
      VaultStorage(_vaultStorage).addTraderToken(_subAccount, _token);
    }

    emit LogDepositCollateral(_primaryAccount, _subAccount, _token, _amount);
  }

  /// @notice Calculate new trader balance after withdraw collateral token.
  /// @dev This uses to calculate new trader balance when they withdrawing token as collateral.
  /// @param _primaryAccount Trader's primary address from trader's wallet.
  /// @param _subAccountId Trader's Sub-Account Id.
  /// @param _token Token that's withdrawn as collateral.
  /// @param _amount Token withdrawing amount.
  function withdrawCollateral(
    address _primaryAccount,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant onlyWhitelistedExecutor onlyAcceptedToken(_token) {
    address _vaultStorage = vaultStorage;

    // Get trader's sub-account address
    address _subAccount = _getSubAccount(_primaryAccount, _subAccountId);

    // Get current collateral token balance of trader's account
    // and deduct with new token withdrawing amount
    uint256 _oldBalance = VaultStorage(_vaultStorage).traderBalances(_subAccount, _token);
    if (_amount > _oldBalance) revert ICrossMarginService_InsufficientBalance();

    uint256 _newBalance = _oldBalance - _amount;

    // Set new collateral token balance
    VaultStorage(_vaultStorage).setTraderBalance(_subAccount, _token, _newBalance);

    // Calculate validation for if new Equity is below IMR or not
    int256 equity = Calculator(calculator).getEquity(_subAccount, 0, 0);
    if (equity < 0 || uint256(equity) < Calculator(calculator).getIMR(_subAccount))
      revert ICrossMarginService_WithdrawBalanceBelowIMR();

    // If trader withdraws all token out, then remove token on traderTokens list
    if (_oldBalance != 0 && _newBalance == 0) {
      VaultStorage(_vaultStorage).removeTraderToken(_subAccount, _token);
    }

    // Transfer withdrawing token from VaultStorage to trader's wallet
    VaultStorage(_vaultStorage).pushToken(_token, _primaryAccount, _amount);

    emit LogWithdrawCollateral(_primaryAccount, _subAccount, _token, _amount);
  }

  /**
   * Setter
   */
  /// @notice Set new ConfigStorage contract address.
  /// @param _configStorage New ConfigStorage contract address.
  function setConfigStorage(address _configStorage) external onlyOwner {
    if (_configStorage == address(0)) revert ICrossMarginService_InvalidAddress();
    emit LogSetConfigStorage(configStorage, _configStorage);
    configStorage = _configStorage;

    // Sanity check
    ConfigStorage(_configStorage).calculator();
  }

  /// @notice Set new VaultStorage contract address.
  /// @param _vaultStorage New VaultStorage contract address.
  function setVaultStorage(address _vaultStorage) external onlyOwner {
    if (_vaultStorage == address(0)) revert ICrossMarginService_InvalidAddress();

    emit LogSetVaultStorage(vaultStorage, _vaultStorage);
    vaultStorage = _vaultStorage;

    // Sanity check
    VaultStorage(_vaultStorage).devFees(address(0));
  }

  /// @notice Set new Calculator contract address.
  /// @param _calculator New Calculator contract address.
  function setCalculator(address _calculator) external onlyOwner {
    if (_calculator == address(0)) revert ICrossMarginService_InvalidAddress();

    emit LogSetCalculator(calculator, _calculator);
    calculator = _calculator;

    // Sanity check
    Calculator(_calculator).oracle();
  }

  /// @notice Calculate subAccount address on trader.
  /// @dev This uses to create subAccount address combined between Primary account and SubAccount ID.
  /// @param _primary Trader's primary wallet account.
  /// @param _subAccountId Trader's sub account ID.
  /// @return _subAccount Trader's sub account address used for trading.
  function _getSubAccount(address _primary, uint256 _subAccountId) internal pure returns (address _subAccount) {
    if (_subAccountId > 255) revert();
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }
}
