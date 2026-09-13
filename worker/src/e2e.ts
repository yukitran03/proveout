import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { Contract, ethers } from 'ethers';

import { artifact, ACTION_CHALLENGE, ACTION_RELEASE } from './artifacts.js';
import {
  CC3_RPC,
  EXPLORER,
  ROOT,
  SEPOLIA_EXPLORER,
  SEPOLIA_RPC,
  need,
  readDeployment,
} from './env.js';
import { proveSourceTx } from './proof.js';
import { submitExpectingRevert, submitProof } from './submit.js';

/**
 * The three transactions the submission stands on:
 *
 *   1. release            — a proved WorkCompleted pays the builder
 *   2. challenge-refund   — a proved WorkFailed, submitted by a wallet that is NEITHER
 *                           the buyer NOR the builder, refunds the buyer and pays the
 *                           submitter a bounty out of the builder's bond
 *   3. replay blocked     — resubmitting proof #1 reverts on-chain
 *
 * Nothing here is simulated. Each waits out a real Attestcoin attestation.
 */

const AMOUNT = 1_000_000_000n; // 1,000 tUSDC at 6 decimals
const JOB_WINDOW = 60 * 60 * 24; // 24 hours

function derive(pk: string, label: string): string {
  return ethers.keccak256(ethers.concat([pk, ethers.toUtf8Bytes(label)]));
}

async function fundGas(from: ethers.Wallet, to: string, amount: bigint, label: string) {
  const bal = await from.provider!.getBalance(to);
  if (bal >= amount) {
    console.log(`  ${label} already holds ${ethers.formatEther(bal)} CTC`);
    return;
  }
  const tx = await from.sendTransaction({ to, value: amount });
  await tx.wait();
  console.log(`  funded ${label} ${to} with ${ethers.formatEther(amount)} CTC`);
}

async function main() {
  const d = readDeployment();
  const pk = need('CREDITCOIN_WALLET_PRIVATE_KEY');

  const cc3 = new ethers.JsonRpcProvider(CC3_RPC);
  const sepolia = new ethers.JsonRpcProvider(SEPOLIA_RPC);

  const buyer = new ethers.Wallet(pk, cc3);
  const buyerOnSepolia = new ethers.Wallet(pk, sepolia);
  const builder = new ethers.Wallet(derive(pk, 'proveout-builder'), cc3);
  const challenger = new ethers.Wallet(derive(pk, 'proveout-challenger'), cc3);

  console.log('actors');
  console.log(`  buyer      ${buyer.address}`);
  console.log(`  builder    ${builder.address}`);
  console.log(`  challenger ${challenger.address}  <- neither buyer nor builder`);

  const escrowAbi = artifact('JobEscrow').abi;
  const escrow = new Contract(d.jobEscrow, escrowAbi, buyer);
  const usdc = new Contract(d.testUsdc, artifact('TestUSDC').abi, buyer);
  const oracle = new Contract(d.workOracle, artifact('WorkOracle').abi, buyerOnSepolia);

  console.log('\npreparing actors');
  await fundGas(buyer, builder.address, ethers.parseEther('1'), 'builder');
  await fundGas(buyer, challenger.address, ethers.parseEther('1'), 'challenger');
  for (const who of [buyer.address, builder.address]) {
    const tx = await (usdc as any).mint(who, AMOUNT * 10n);
    await tx.wait();
  }
  await (await (usdc as any).approve(d.jobEscrow, ethers.MaxUint256)).wait();
  await (await (usdc.connect(builder) as any).approve(d.jobEscrow, ethers.MaxUint256)).wait();
  console.log('  tUSDC minted and approved');

  const results: Record<string, unknown> = { deployment: d, scenarios: {} };
  const scenarios = results.scenarios as Record<string, unknown>;

  async function openJob(label: string): Promise<{ jobId: string; criteria: string }> {
    const jobId = ethers.id(`proveout-${label}-${Date.now()}`);
    const criteria = ethers.id(`criteria:${label}:deliver-and-pass-ci`);
    const deadline = Math.floor(Date.now() / 1000) + JOB_WINDOW;

    await (await (escrow as any).createJob(jobId, builder.address, AMOUNT, deadline, criteria, d.workOracle)).wait();
    await (await (escrow.connect(builder) as any).postBond(jobId)).wait();
    await (await (escrow as any).fundJob(jobId)).wait();
    console.log(`  job ${label} funded: ${jobId}`);
    return { jobId, criteria };
  }

  // ------------------------------------------------------ 1. release
  console.log('\n=== SCENARIO 1: release on proved completion ===');
  const job1 = await openJob('release');
  const completed = await (oracle as any).reportCompleted(
    job1.jobId,
    job1.criteria,
    builder.address,
    ethers.id('artifact-v1'),
  );
  console.log(`  Sepolia WorkCompleted: ${completed.hash}`);
  const proof1 = await proveSourceTx(completed.hash, cc3, sepolia);

  const builderBefore = await (usdc as any).balanceOf(builder.address);
  const r1 = await submitProof(escrow, ACTION_RELEASE, proof1, buyer);
  const builderAfter = await (usdc as any).balanceOf(builder.address);
  console.log(`  builder received ${ethers.formatUnits(builderAfter - builderBefore, 6)} tUSDC`);
  scenarios.release = {
    jobId: job1.jobId,
    sourceTx: completed.hash,
    sourceTxUrl: `${SEPOLIA_EXPLORER}/tx/${completed.hash}`,
    settlementTx: r1.hash,
    settlementTxUrl: `${EXPLORER}/tx/${r1.hash}`,
    paidToBuilder: (builderAfter - builderBefore).toString(),
    status: Number(r1.status),
  };

  // ---------------------------------------------- 2. challenge refund
  console.log('\n=== SCENARIO 2: anyone forces a refund with a failure proof ===');
  const job2 = await openJob('challenge');
  const failed = await (oracle as any).reportFailed(job2.jobId, ethers.id('criteria-not-met'));
  console.log(`  Sepolia WorkFailed: ${failed.hash}`);
  const proof2 = await proveSourceTx(failed.hash, cc3, sepolia);

  const buyerBefore = await (usdc as any).balanceOf(buyer.address);
  const chalBefore = await (usdc as any).balanceOf(challenger.address);
  const r2 = await submitProof(escrow.connect(challenger) as Contract, ACTION_CHALLENGE, proof2, challenger);
  const buyerAfter = await (usdc as any).balanceOf(buyer.address);
  const chalAfter = await (usdc as any).balanceOf(challenger.address);
  console.log(`  buyer refunded  ${ethers.formatUnits(buyerAfter - buyerBefore, 6)} tUSDC`);
  console.log(`  challenger paid ${ethers.formatUnits(chalAfter - chalBefore, 6)} tUSDC bounty`);
  scenarios.challenge = {
    jobId: job2.jobId,
    challenger: challenger.address,
    sourceTx: failed.hash,
    sourceTxUrl: `${SEPOLIA_EXPLORER}/tx/${failed.hash}`,
    settlementTx: r2.hash,
    settlementTxUrl: `${EXPLORER}/tx/${r2.hash}`,
    refundedToBuyer: (buyerAfter - buyerBefore).toString(),
    bountyToChallenger: (chalAfter - chalBefore).toString(),
    status: Number(r2.status),
  };

  // --------------------------------------------------- 3. replay blocked
  console.log('\n=== SCENARIO 3: replaying proof #1 is refused ===');
  const replay = await submitExpectingRevert(escrow, ACTION_RELEASE, proof1, buyer);
  scenarios.replay = {
    reusedProofFrom: completed.hash,
    settlementTx: replay.hash,
    settlementTxUrl: `${EXPLORER}/tx/${replay.hash}`,
    revertReason: replay.reason,
  };

  mkdirSync(join(ROOT, 'deployments'), { recursive: true });
  const out = join(ROOT, 'deployments', 'e2e-results.json');
  writeFileSync(out, JSON.stringify(results, null, 2) + '\n');
  console.log(`\nwrote ${out}`);
  console.log('\nThree real transactions:');
  console.log(`  release   ${EXPLORER}/tx/${r1.hash}`);
  console.log(`  challenge ${EXPLORER}/tx/${r2.hash}`);
  console.log(`  replay    ${EXPLORER}/tx/${replay.hash}  (reverted, on purpose)`);
}

main().catch((e) => {
  console.error('E2E FAILED:', e?.shortMessage ?? e?.message ?? e);
  process.exit(1);
});
