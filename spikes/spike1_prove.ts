/**
 * SPIKE 1 — Death gate for ProveOut.
 * Proves ONE real Sepolia transaction on Creditcoin CC3 via the Block Prover
 * precompile and prints its receiptStatus + decoded event logs.
 *
 * Uses eth_call (verifySingle) so it needs NO funded wallet.
 */
import { ethers } from 'ethers';
import { proofProvider, blockProver, chainInfo } from '@gluwa/usc-sdk';

const CC3_RPC = 'https://rpc.cc3-testnet.creditcoin.network';
const PROVER = 'https://prover.cc3-testnet.creditcoin.network';
const SOURCE_CHAIN_KEY = 1; // Ethereum Sepolia on CC3 Testnet (NOT chain id 11155111)
// Known burn tx on the pre-deployed tutorial TestERC20 (Sepolia).
const TX = process.argv[2] ?? '0x87c97c776a678941b5941ec0cb602a4467ff4a35f77264208575f137cb05b2a7';

const abi = ethers.AbiCoder.defaultAbiCoder();

function decodeReceipt(txBytes: string) {
  const [txType, chunks] = abi.decode(['uint8', 'bytes[]'], txBytes);
  const receiptIdx = Number(txType) <= 2 ? 2 : 3;
  const [status, gasUsed, logs] = abi.decode(
    ['uint8', 'uint64', 'tuple(address,bytes32[],bytes)[]', 'bytes'],
    chunks[receiptIdx],
  );
  return { txType: Number(txType), status: Number(status), gasUsed: gasUsed.toString(), logs };
}

async function main() {
  const cc3 = new ethers.JsonRpcProvider(CC3_RPC);
  console.log('CC3 chainId  :', (await cc3.getNetwork()).chainId.toString());

  const info = new chainInfo.PrecompileChainInfoProvider(cc3);
  const att = await info.getLatestAttestedHeightAndHash(SOURCE_CHAIN_KEY);
  console.log('Latest attested Sepolia height on CC3:', att.height);

  console.log('\nFetching proof for', TX, '...');
  const res = await new proofProvider.service.ProofBuilder(SOURCE_CHAIN_KEY, PROVER).getProof(TX);
  if (!res.success) throw new Error('proof failed: ' + JSON.stringify(res));
  const p = res.data!;
  console.log('  headerNumber :', p.headerNumber);
  console.log('  txIndex      :', p.txIndex);
  console.log('  merkle sibs  :', p.merkleProof.siblings.length);
  console.log('  continuity   :', p.continuityProof.roots.length, 'roots');
  console.log('  txBytes len  :', (p.txBytes.length - 2) / 2, 'bytes');

  console.log('\n>>> Calling precompile 0x..0FD2 verifySingle() via eth_call (no gas)...');
  const prover = new blockProver.PrecompileBlockProver(cc3);
  const ok = await prover.verifySingle(
    p.chainKey, p.headerNumber, p.txBytes, p.merkleProof, p.continuityProof,
  );
  console.log('PRECOMPILE verify  =>', ok);
  const idx = await prover.computeTransactionIndex(p.merkleProof);
  console.log('computeTxIndex     =>', idx);

  const r = decodeReceipt(p.txBytes);
  console.log('\n--- DECODED (EvmV1Decoder layout) ---');
  console.log('txType        :', r.txType);
  console.log('RECEIPTSTATUS :', r.status, r.status === 1 ? '(SUCCESS)' : '(REVERTED)');
  console.log('gasUsed       :', r.gasUsed);
  console.log('logs          :', r.logs.length);
  r.logs.forEach((l: any, i: number) => {
    console.log(`  [${i}] emitter=${l[0]}`);
    l[1].forEach((t: string, j: number) => console.log(`      topic${j}=${t}`));
    console.log(`      data=${l[2]}`);
  });
  if (!ok || r.status !== 1) throw new Error('GATE FAILED');
  console.log('\n*** DEATH GATE PASSED ***');
}
main().catch((e) => { console.error('SPIKE FAILED:', e?.message ?? e); process.exit(1); });
