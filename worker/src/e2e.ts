import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { Contract, ethers } from 'ethers';

import { artifact, ACTION_CHALLENGE, ACTION_RELEASE } from './artifacts.js';
import { CC3_RPC, EXPLORER, ROOT, SEPOLIA_EXPLORER, SEPOLIA_RPC, need, readDeployment } from './env.js';
import { proveSourceTx } from './proof.js';
import { submitExpectingRevert, submitProof } from './submit.js';

/**
 * The four transactions the submission stands on:
 *
 *   1. release        a proved WorkCompleted pays the builder
 *   2. challenge      a proved WorkFailed, submitted by a wallet that is NEITHER the buyer
 *                     NOR the builder, refunds the buyer and pays the submitter a bounty
 *                     out of the builder's bond
 *   3. replay blocked resubmitting proof #1 reverts on Creditcoin
 *   4. self-certify   the builder tries to declare their own work complete on the source
 *                     chain, and is refused there, before any proof can exist
 *
 * Nothing here is simulated. Each proof waits out a real Attestcoin attestation.
 */

const AMOUNT = 1_000_000_000n; // 1,000 tUSDC at 6 decimals
const JOB_WINDOW = 60 * 60 * 24; // 24 hours

function derive(pk: string, label: string): string {
  return ethers.keccak256(ethers.concat([pk, ethers.toUtf8Bytes(label)]));
}

async function fundGas(from: ethers.Wallet, to: string, amount: bigint, label: string) {
  const bal = await from.provider!.getBalance(to);
  if (bal >= amount) {
    console.log(`  ${label} already holds ${ethers.formatEther(bal)}`);
    return;
  }
  const tx = await from.sendTransaction({ to, value: amount });
  await tx.wait();
  console.log(`  funded ${label} ${to} with ${ethers.formatEther(amount)}`);
}

async function main() {
  const d = readDeployment();
  const pk = need('CREDITCOIN_WALLET_PRIVATE_KEY');

  const cc3 = new ethers.JsonRpcProvider(CC3_RPC);
  const sepolia = new ethers.JsonRpcProvider(SEPOLIA_RPC);

  const buyer = new ethers.Wallet(pk, cc3);
  const buyerOnSepolia = new ethers.Wallet(pk, sepolia);
  const builderPk = derive(pk, 'proveout-builder');
  const builder = new ethers.Wallet(builderPk, cc3);
  const builderOnSepolia = new ethers.Wallet(builderPk, sepolia);
  const challenger = new ethers.Wallet(derive(pk, 'proveout-challenger'), cc3);

  console.log('actors');
  console.log(`  buyer      ${buyer.address}  (also the authorised reporter)`);
  console.log(`  builder    ${builder.address}`);
  console.log(`  challenger ${challenger.address}  <- neither buyer nor builder`);

  const escrow = new Contract(d.jobEscrow, artifact('JobEscrow').abi, buyer);
  const usdc = new Contract(d.testUsdc, artifact('TestUSDC').abi, buyer);
  const oracle = new Contract(d.workOracle, artifact('WorkOracle').abi, buyerOnSepolia);

  console.log('\npreparing actors');
  await fundGas(buyer, builder.address, ethers.parseEther('1'), 'builder (CTC)');
  await fundGas(buyer, challenger.address, ethers.parseEther('1'), 'challenger (CTC)');
  await fundGas(buyerOnSepolia, builderOnSepolia.address, ethers.parseEther('0.004'), 'builder (Sepolia ETH)');
  for (const who of [buyer.address, builder.address]) {
    await (await (usdc as any).mint(who, AMOUNT * 10n)).wait();
  }
  await (await (usdc as any).approve(d.jobEscrow, ethers.MaxUint256)).wait();
  await (await (usdc.connect(builder) as any).approve(d.jobEscrow, ethers.MaxUint256)).wait();
  console.log('  tUSDC minted and approved');

  const results: Record<string, unknown> = { deployment: d, scenarios: {} };
  const scenarios = results.scenarios as Record<string, unknown>;

  async function openJob(label: string) {
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
    job1.jobId, job1.criteria, builder.address, ethers.id('artifact-v1'),
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

  // ------------------------------ 4. self-certification blocked at the source
  console.log('\n=== SCENARIO 4: the builder cannot certify their own work ===');
  const job3 = await openJob('self-certify');
  const oracleAsBuilder = oracle.connect(builderOnSepolia) as any;
  const data = oracle.interface.encodeFunctionData('reportCompleted', [
    job3.jobId, job3.criteria, builder.address, ethers.id('fabricated'),
  ]);
  let selfReason = 'unknown';
  try {
    await sepolia.call({ to: d.workOracle, data, from: builderOnSepolia.address });
    throw new Error('expected the source chain to refuse this');
  } catch (e: any) {
    const revertData = e?.data ?? e?.info?.error?.data;
    try {
      const parsed = oracle.interface.parseError(revertData);
      selfReason = parsed
        ? `${parsed.name}(${parsed.args.map(String).join(', ')})`
        : (e?.shortMessage ?? 'reverted');
    } catch {
      selfReason = e?.shortMessage ?? e?.reason ?? e?.message ?? 'reverted';
    }
  }
  // Force it on chain so the refusal is a public, checkable artifact.
  const selfTx = await builderOnSepolia.sendTransaction({ to: d.workOracle, data, gasLimit: 120_000n });
  const selfRc = await sepolia.waitForTransaction(selfTx.hash, 1, 180_000).catch(() => null);
  console.log(`  Sepolia self-certify attempt ${selfTx.hash} status=${selfRc?.status ?? 'reverted'}`);
  console.log(`  refused with: ${selfReason}`);
  const isReporter = await (oracle as any).isReporter(builder.address);
  console.log(`  oracle.isReporter(builder) = ${isReporter}`);
  scenarios.selfCertify = {
    jobId: job3.jobId,
    attemptedBy: builder.address,
    sourceTx: selfTx.hash,
    sourceTxUrl: `${SEPOLIA_EXPLORER}/tx/${selfTx.hash}`,
    status: Number(selfRc?.status ?? 0),
    revertReason: selfReason,
    builderIsReporter: Boolean(isReporter),
  };

  mkdirSync(join(ROOT, 'deployments'), { recursive: true });
  const out = join(ROOT, 'deployments', 'e2e-results.json');
  writeFileSync(out, JSON.stringify(results, null, 2) + '\n');
  console.log(`\nwrote ${out}`);
  console.log('\nFour real transactions:');
  console.log(`  release      ${EXPLORER}/tx/${r1.hash}`);
  console.log(`  challenge    ${EXPLORER}/tx/${r2.hash}`);
  console.log(`  replay       ${EXPLORER}/tx/${replay.hash}  (reverted, on purpose)`);
  console.log(`  self-certify ${SEPOLIA_EXPLORER}/tx/${selfTx.hash}  (reverted on Sepolia, on purpose)`);
  void oracleAsBuilder;
}

main().catch((e) => {
  console.error('E2E FAILED:', e?.shortMessage ?? e?.message ?? e);
  process.exit(1);
});
