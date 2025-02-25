// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IGmxGlpManager } from "@hmx/interfaces/gmx/IGmxGlpManager.sol";
import { StakedGlpOracleAdapter } from "@hmx/oracles/StakedGlpOracleAdapter.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";

import { TestBase } from "forge-std/Base.sol";
import { StdCheatsSafe } from "forge-std/StdCheats.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { IERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakedGlpOracleAdapter_GetLatestPrice is TestBase, StdAssertions, StdCheatsSafe {
  bytes32 public constant sGlpAssetId = "sGLP";
  IOracleAdapter stakedGlpOracleAdapter;

  uint256 arbitrumForkId = vm.createSelectFork(vm.rpcUrl("arbitrum_fork"));
  address public constant glpAddress = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
  address public constant glpManagerAddress = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;

  ProxyAdmin proxyAdmin;

  function setUp() public {
    proxyAdmin = new ProxyAdmin();

    stakedGlpOracleAdapter = Deployer.deployStakedGlpOracleAdapter(
      address(proxyAdmin),
      IERC20Upgradeable(address(glpAddress)),
      IGmxGlpManager(glpManagerAddress),
      sGlpAssetId
    );
  }

  function testCorrectnesss_WhenGetGlpLatestPriceMaxPrice() external {
    (uint256 price, uint256 timestamp) = stakedGlpOracleAdapter.getLatestPrice(sGlpAssetId, true, 0);
    uint256 maxPrice = IGmxGlpManager(glpManagerAddress).getAum(true);
    uint256 minPrice = IGmxGlpManager(glpManagerAddress).getAum(false);
    uint256 avgPrice = (((maxPrice + minPrice) / 2) * 1e18) / ERC20(glpAddress).totalSupply();
    assertEq(price, avgPrice);
    assertEq(timestamp, block.timestamp);
  }

  function testCorrectnesss_WhenGetGlpLatestPriceMinPrice() external {
    (uint256 price, uint256 timestamp) = stakedGlpOracleAdapter.getLatestPrice(sGlpAssetId, false, 0);
    uint256 maxPrice = IGmxGlpManager(glpManagerAddress).getAum(true);
    uint256 minPrice = IGmxGlpManager(glpManagerAddress).getAum(false);
    uint256 avgPrice = (((maxPrice + minPrice) / 2) * 1e18) / ERC20(glpAddress).totalSupply();
    assertEq(price, avgPrice);
    assertEq(timestamp, block.timestamp);
  }
}
