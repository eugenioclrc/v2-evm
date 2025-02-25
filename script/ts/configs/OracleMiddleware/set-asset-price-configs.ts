import { ethers } from "ethers";
import { OracleMiddleware__factory } from "../../../../typechain";
import { loadConfig } from "../../utils/config";
import signers from "../../entities/signers";
import { Command } from "commander";

async function main(chainId: number) {
  const config = loadConfig(chainId);
  const assetConfigs = [
    {
      assetId: ethers.utils.formatBytes32String("QQQ"),
      confidenceThreshold: 0,
      trustPriceAge: 60 * 60 * 24 * 3, // 3 days
      adapter: config.oracles.pythAdapter,
    },
    {
      assetId: ethers.utils.formatBytes32String("XRP"),
      confidenceThreshold: 0,
      trustPriceAge: 60 * 5, // 5 minutes
      adapter: config.oracles.pythAdapter,
    },
  ];

  const deployer = signers.deployer(chainId);
  const oracle = OracleMiddleware__factory.connect(config.oracles.middleware, deployer);

  console.log("[OracleMiddleware] Setting asset price configs...");
  const tx = await oracle.setAssetPriceConfigs(
    assetConfigs.map((each) => each.assetId),
    assetConfigs.map((each) => each.confidenceThreshold),
    assetConfigs.map((each) => each.trustPriceAge),
    assetConfigs.map((each) => each.adapter)
  );
  console.log(`[OracleMiddleware] Tx: ${tx.hash}`);
  await tx.wait(1);
  console.log("[OracleMiddleware] Finished");
}

const prog = new Command();

prog.requiredOption("--chain-id <chainId>", "chain id", parseInt);

prog.parse(process.argv);

const opts = prog.opts();

main(opts.chainId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
