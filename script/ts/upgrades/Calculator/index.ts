import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, tenderly, upgrades, network } from "hardhat";
import { getConfig, writeConfigFile } from "../../utils/config";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

const BigNumber = ethers.BigNumber;
const config = getConfig();

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const Contract = await ethers.getContractFactory("Calculator", deployer);
  const TARGET_ADDRESS = config.calculator;

  console.log(`> Preparing to upgrade Calculator`);
  const newImplementation = await upgrades.prepareUpgrade(TARGET_ADDRESS, Contract);
  console.log(`> Done`);

  console.log(`> New Calculator Implementation address: ${newImplementation}`);
  const upgradeTx = await upgrades.upgradeProxy(TARGET_ADDRESS, Contract);
  console.log(`> ⛓ Tx is submitted: ${upgradeTx.deployTransaction.hash}`);
  console.log(`> Waiting for tx to be mined...`);
  await upgradeTx.deployTransaction.wait(3);
  console.log(`> Tx is mined!`);

  console.log(`> Verify contract on Tenderly`);
  await tenderly.verify({
    address: newImplementation.toString(),
    name: "Calculator",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
