// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

interface ITradeServiceHook {
  /**
   * Functions
   */
  function onIncreasePosition(
    address primaryAccount,
    uint256 subAccountId,
    uint256 marketIndex,
    uint256 sizeDelta,
    bytes32 data
  ) external;

  function onDecreasePosition(
    address primaryAccount,
    uint256 subAccountId,
    uint256 marketIndex,
    uint256 sizeDelta,
    bytes32 data
  ) external;
}
