import { OwnableUpgradeable__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import { Command } from "commander";
import signers from "../../entities/signers";
import * as readlineSync from "readline-sync";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const deployer = signers.deployer(chainId);

  const newOwner = config.safe;
  const confirm = readlineSync.question(`Confirm new owner is ${newOwner}? (y/n): `);
  switch (confirm) {
    case "y":
      break;
    case "n":
      console.log("Cancelled!");
      return;
    default:
      console.log("Invalid input!");
      return;
  }

  const contracts = [
    config.storages.config,
    config.storages.perp,
    config.storages.vault,
    config.handlers.bot,
    config.handlers.crossMargin,
    config.handlers.limitTrade,
    config.handlers.liquidity,
    config.oracles.ecoPyth,
    config.oracles.ecoPyth2,
    config.oracles.middleware,
    config.oracles.pythAdapter,
    config.oracles.sglpStakedAdapter,
    config.tokens.hlp,
    config.strategies.stakedGlpStrategy,
    config.strategies.convertedGlpStrategy,
    config.calculator,
    config.rewardDistributor,
  ];

  console.log(`[config/Ownable] Transfer Ownership to ${newOwner}...`);
  let nonce = await deployer.getTransactionCount()
  const promises = []
  for (let i = 0; i < contracts.length; i++) {
    const ownable = OwnableUpgradeable__factory.connect(contracts[i], deployer);
    promises.push(ownable.transferOwnership(newOwner, { nonce: nonce++}));
  }
  const txs = await Promise.all(promises)
  await txs[txs.length - 1].wait(1)
  console.log(`[config/Ownable] Ownership transferred!`);
}

const prog = new Command();

prog.requiredOption("--chain-id <number>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId)
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
