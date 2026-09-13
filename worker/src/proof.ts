import { ethers } from 'ethers';
import { chainInfo, proofProvider } from '@gluwa/usc-sdk';
import { PROOF_BUILDER_URL, SOURCE_CHAIN_KEY } from './env.js';

export type ProofData = proofProvider.ContinuityResponse;

/**
 * Waits for a Sepolia block to be attested on Creditcoin, then fetches its proof.
 *
 * The wait is real and not skippable: Attestcoin deliberately lags the source chain head
 * (~8-10 minutes on Sepolia) so a source-chain reorg cannot be attested into permanence.
 * Anything that claims to settle a fresh source transaction instantly is not using this
 * protocol correctly.
 */
export async function proveSourceTx(
  txHash: string,
  cc3: ethers.JsonRpcProvider,
  sepolia: ethers.JsonRpcProvider,
): Promise<ProofData> {
  const receipt = await sepolia.waitForTransaction(txHash, 1, 180_000);
  if (!receipt || receipt.blockNumber == null) {
    throw new Error(`Sepolia tx ${txHash} is not mined`);
  }
  if (receipt.status !== 1) {
    throw new Error(`Sepolia tx ${txHash} reverted; there is nothing worth proving`);
  }
  console.log(`  source tx in block ${receipt.blockNumber} (status ${receipt.status})`);

  const info = new chainInfo.PrecompileChainInfoProvider(cc3);
  const attested = await info.getLatestAttestedHeightAndHash(SOURCE_CHAIN_KEY);
  const lag = receipt.blockNumber - Number(attested.height);
  console.log(
    `  latest attested height ${attested.height} (${lag > 0 ? `${lag} blocks behind` : 'already ahead'})`,
  );

  const builder = new proofProvider.service.ProofBuilder(SOURCE_CHAIN_KEY, PROOF_BUILDER_URL);
  console.log('  waiting for attestation (expect ~8-10 minutes)...');
  await builder.waitUntilHeightAttested(SOURCE_CHAIN_KEY, receipt.blockNumber, 15_000, 1_500_000);

  const result = await builder.getProof(txHash);
  if (!result.success || !result.data) {
    throw new Error(`proof generation failed: ${result.error}`);
  }
  const d = result.data;
  console.log(
    `  proof ready: height=${d.headerNumber} txIndex=${d.txIndex} ` +
      `siblings=${d.merkleProof.siblings.length} continuity=${d.continuityProof.roots.length}`,
  );
  return d;
}

/** Arguments for ASCBase.execute, in the protocol's exact parameter order. */
export function executeArgs(action: number, p: ProofData) {
  return [
    action,
    p.chainKey,
    p.headerNumber,
    p.txBytes,
    p.merkleProof.root,
    p.merkleProof.siblings,
    p.continuityProof.lowerEndpointDigest,
    p.continuityProof.roots,
  ] as const;
}
