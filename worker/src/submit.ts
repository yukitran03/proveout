import { Contract, ethers } from 'ethers';
import { EXECUTE_SIGNATURE } from './artifacts.js';
import { executeArgs, type ProofData } from './proof.js';

/**
 * Submits a proof to JobEscrow.execute.
 *
 * Gas is estimated with a fallback because pallet-evm does not reliably propagate revert
 * reasons during estimation when a precompile is in the call path — Gluwa's own examples
 * hit the same thing and calculate from proof size instead. A failed estimate here does
 * not mean the call would fail.
 */
export async function submitProof(
  escrow: Contract,
  action: number,
  proof: ProofData,
  signer: ethers.Signer,
): Promise<ethers.TransactionReceipt> {
  const args = executeArgs(action, proof);
  const fn = escrow.interface.getFunction(EXECUTE_SIGNATURE);
  if (!fn) throw new Error('JobEscrow is missing the ASCBase execute() fragment');
  const data = escrow.interface.encodeFunctionData(fn, args as unknown as any[]);
  const to = await escrow.getAddress();
  const from = await signer.getAddress();

  let gasLimit: bigint;
  try {
    const est = await signer.provider!.estimateGas({ to, data, from });
    gasLimit = (est * 135n) / 100n;
    console.log(`  gas estimated ${est} -> limit ${gasLimit}`);
  } catch (e: any) {
    gasLimit = BigInt(21_000 + proof.continuityProof.roots.length * 5_000 + 400_000);
    console.warn(`  gas estimation unavailable (${e?.shortMessage ?? e?.message}); using ${gasLimit}`);
  }

  const sent = await signer.sendTransaction({ to, data, gasLimit });
  console.log(`  submitted ${sent.hash}`);
  const receipt = await sent.wait();
  if (!receipt) throw new Error('no receipt');
  return receipt;
}

/**
 * Submits a proof that is EXPECTED to revert, and returns the hash of the reverted
 * transaction. Used for the replay demo: a blocked replay is only convincing if you can
 * point at the on-chain transaction that failed.
 */
export async function submitExpectingRevert(
  escrow: Contract,
  action: number,
  proof: ProofData,
  signer: ethers.Signer,
): Promise<{ hash: string; reason: string }> {
  const args = executeArgs(action, proof);
  const fn = escrow.interface.getFunction(EXECUTE_SIGNATURE)!;
  const data = escrow.interface.encodeFunctionData(fn, args as unknown as any[]);
  const to = await escrow.getAddress();

  let reason = 'unknown';
  try {
    await signer.provider!.call({ to, data, from: await signer.getAddress() });
    throw new Error('expected the call to revert, but it succeeded');
  } catch (e: any) {
    reason = e?.shortMessage ?? e?.reason ?? e?.message ?? 'reverted';
  }

  // Force it on-chain anyway so the failure is a public, checkable artifact.
  const sent = await signer.sendTransaction({ to, data, gasLimit: 900_000n });
  const receipt = await sent.wait(1, 120_000).catch(() => null);
  console.log(`  replay tx ${sent.hash} status=${receipt?.status ?? 'reverted'} (${reason})`);
  return { hash: sent.hash, reason };
}
