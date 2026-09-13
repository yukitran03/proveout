import { Contract, ethers } from 'ethers';
import { artifact, ACTION_CHALLENGE, ACTION_RELEASE } from './artifacts.js';
import { CC3_RPC, EXPLORER, SEPOLIA_RPC, need, readDeployment } from './env.js';
import { proveSourceTx } from './proof.js';
import { submitProof } from './submit.js';

/**
 * Offchain settlement worker.
 *
 * It is worth being precise about what this process is and is not. It is a RELAYER: it
 * watches the source chain, fetches proofs, and pays gas to submit them. It is not an
 * oracle and it is not trusted. It cannot make the escrow pay anyone, cannot choose which
 * job settles, and cannot forge a result — every one of those decisions is made on-chain
 * from the proved event. If this worker disappears, anyone can submit the same proofs and
 * the escrow behaves identically. If it lies, the contract rejects it.
 *
 * That is the whole difference from an operator-run oracle, and it is why the worker is
 * allowed to be this small.
 */

const POLL_MS = 20_000;

async function main() {
  const d = readDeployment();
  const pk = need('CREDITCOIN_WALLET_PRIVATE_KEY');
  const cc3 = new ethers.JsonRpcProvider(CC3_RPC);
  const sepolia = new ethers.JsonRpcProvider(SEPOLIA_RPC);
  const relayer = new ethers.Wallet(pk, cc3);

  const escrow = new Contract(d.jobEscrow, artifact('JobEscrow').abi, relayer);
  const oracle = new Contract(d.workOracle, artifact('WorkOracle').abi, sepolia);

  const from = Number(process.env.FROM_BLOCK ?? (await sepolia.getBlockNumber()) - 500);
  console.log(`relayer ${relayer.address}`);
  console.log(`watching ${d.workOracle} on Sepolia from block ${from}`);

  const seen = new Set<string>();
  let cursor = from;

  for (;;) {
    try {
      const head = await sepolia.getBlockNumber();
      if (head >= cursor) {
        const logs = await oracle.queryFilter('*', cursor, head);
        for (const log of logs) {
          const parsed = oracle.interface.parseLog({ topics: [...log.topics], data: log.data });
          if (!parsed) continue;
          if (seen.has(log.transactionHash)) continue;
          seen.add(log.transactionHash);

          const action =
            parsed.name === 'WorkCompleted'
              ? ACTION_RELEASE
              : parsed.name === 'WorkFailed'
                ? ACTION_CHALLENGE
                : null;
          if (action === null) continue;

          console.log(`\n${parsed.name} jobId=${parsed.args[0]} tx=${log.transactionHash}`);
          try {
            const proof = await proveSourceTx(log.transactionHash, cc3, sepolia);
            const receipt = await submitProof(escrow, action, proof, relayer);
            console.log(`  settled: ${EXPLORER}/tx/${receipt.hash}`);
          } catch (e: any) {
            // A rejection here is usually the escrow doing its job: the event names a job
            // this escrow does not have, or it was already settled.
            console.warn(`  not settled: ${e?.shortMessage ?? e?.message}`);
          }
        }
        cursor = head + 1;
      }
    } catch (e: any) {
      console.warn(`poll error: ${e?.shortMessage ?? e?.message}`);
    }
    await new Promise((r) => setTimeout(r, POLL_MS));
  }
}

main().catch((e) => {
  console.error('WORKER FAILED:', e?.shortMessage ?? e?.message ?? e);
  process.exit(1);
});
