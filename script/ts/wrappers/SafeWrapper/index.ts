import Safe from "@safe-global/safe-core-sdk";
import { EthAdapter, SafeTransactionDataPartial } from "@safe-global/safe-core-sdk-types";
import EthersAdapter from "@safe-global/safe-ethers-lib";
import SafeServiceClient from "@safe-global/safe-service-client";
import { ethers } from "ethers";
import chains from "../../entities/chains";
import { SafeProposeTransactionOptions } from "./type";
import { loadConfig } from "../../utils/config";

export default class SafeWrapper {
  private _safeAddress: string;
  private _ethAdapter: EthAdapter;
  private _safeServiceClient: SafeServiceClient;
  private _signer: ethers.Signer;

  constructor(chainId: number, signer: ethers.Signer) {
    const chainInfo = chains[chainId];
    const config = loadConfig(chainId);
    this._safeAddress = config.safe;
    this._ethAdapter = new EthersAdapter({
      ethers,
      signerOrProvider: signer,
    });
    this._safeServiceClient = new SafeServiceClient({
      txServiceUrl: chainInfo.safeTxServiceUrl,
      ethAdapter: this._ethAdapter,
    });
    this._signer = signer;
  }

  getAddress(): string {
    return this._safeAddress;
  }

  async proposeTransaction(
    to: string,
    value: ethers.BigNumberish,
    data: string,
    opts?: SafeProposeTransactionOptions
  ): Promise<string> {
    const safeSdk = await Safe.create({
      ethAdapter: this._ethAdapter,
      safeAddress: this._safeAddress,
    });

    let whichNonce = 0;
    if (opts) {
      // Handling nonce
      if (opts.nonce) {
        // If options has nonce, use it
        whichNonce = opts.nonce;
      } else {
        // If options has no nonce, get next nonce from safe service
        whichNonce = await this._safeServiceClient.getNextNonce(this._safeAddress);
      }
    } else {
      // If options is undefined, get next nonce from safe service
      whichNonce = await this._safeServiceClient.getNextNonce(this._safeAddress);
    }

    const safeTransactionData: SafeTransactionDataPartial = {
      to,
      value: value.toString(),
      data,
      nonce: whichNonce,
    };

    const safeTransaction = await safeSdk.createTransaction({
      safeTransactionData,
    });
    const senderAddress = await this._signer.getAddress();
    const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);
    const signature = await safeSdk.signTransactionHash(safeTxHash);

    await this._safeServiceClient.proposeTransaction({
      safeAddress: this._safeAddress,
      safeTransactionData: safeTransaction.data,
      safeTxHash,
      senderAddress,
      senderSignature: signature.data,
    });

    return safeTxHash;
  }
}
