import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { ContractFactory, ethers } from 'ethers';
import { artifact } from './artifacts.js';
import {
  CC3_CHAIN_ID,
  CC3_RPC,
  ROOT,
  SEPOLIA_RPC,
  SOURCE_CHAIN_KEY,
  SOURCE_EVM_CHAIN_ID,
  need,
} from './env.js';

/**
 * Deploys both halves, and is safe to run repeatedly.
 *
 * It deploys per chain and records each result immediately, because the two faucets this
 * project depends on are independent and land at different times. A run with only one
 * chain funded gets that half deployed and says plainly what is still missing, rather than
 * refusing to do the half it can. A second run reuses what already exists instead of
 * orphaning it.
 */

const BOND_BPS = 2_000; // builder stakes 20% of the job amount
const BOUNTY_BPS = 5_000; // a successful challenger takes half of that bond

export const TOPIC_COMPLETED = ethers.id('WorkCompleted(bytes32,bytes32,address,bytes32)');
export const TOPIC_FAILED = ethers.id('WorkFailed(bytes32,bytes32)');
export const TOPIC_TRANSFER = ethers.id('Transfer(address,address,uint256)');

/**
 * Canonical WETH9 on Ethereum Sepolia. Verified on chain before it was written here: it
 * reports name "Wrapped Ether", symbol "WETH", and carries 3,124 bytes of code.
 *
 * This is the point of the Delivery source kind. It is an ordinary token deployed by people
 * who have never heard of this project, it cannot be configured by anyone here, and it emits
 * Transfer only when tokens actually move. A job settled against it asks nobody whether the
 * work was done.
 */
export const SEPOLIA_WETH = '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14';

const PATH = join(ROOT, 'deployments', 'cc3-testnet.json');

type Partial_ = {
  network?: { creditcoinChainId: number; sourceChainKey: number; sourceEvmChainId: number };
  workOracle?: string;
  deployBlock?: number;
  sepoliaWeth?: string;
  testUsdc?: string;
  sourceRegistry?: string;
  jobEscrow?: string;
  deployedAt?: string;
  deployer?: string;
};

function load(): Partial_ {
  return existsSync(PATH) ? (JSON.parse(readFileSync(PATH, 'utf8')) as Partial_) : {};
}

function save(d: Partial_) {
  mkdirSync(join(ROOT, 'deployments'), { recursive: true });
  writeFileSync(PATH, JSON.stringify(d, null, 2) + '\n');
}

async function deploy(name: string, signer: ethers.Signer, args: unknown[] = []) {
  const { abi, bytecode } = artifact(name);
  const c = await new ContractFactory(abi, bytecode, signer).deploy(...args);
  await c.waitForDeployment();
  const address = await c.getAddress();
  console.log(`  ${name.padEnd(16)} ${address}`);
  return { address, contract: c };
}

async function main() {
  const pk = need('CREDITCOIN_WALLET_PRIVATE_KEY');
  const cc3 = new ethers.JsonRpcProvider(CC3_RPC);
  const sepolia = new ethers.JsonRpcProvider(SEPOLIA_RPC);
  const onCc3 = new ethers.Wallet(pk, cc3);
  const onSepolia = new ethers.Wallet(pk, sepolia);

  const cc3Id = Number((await cc3.getNetwork()).chainId);
  if (cc3Id !== CC3_CHAIN_ID) throw new Error(`expected CC3 chain ${CC3_CHAIN_ID}, got ${cc3Id}`);
  const sepId = Number((await sepolia.getNetwork()).chainId);
  if (sepId !== SOURCE_EVM_CHAIN_ID) {
    throw new Error(`expected source chain ${SOURCE_EVM_CHAIN_ID}, got ${sepId}`);
  }

  const ctc = await cc3.getBalance(onCc3.address);
  const eth = await sepolia.getBalance(onSepolia.address);
  console.log(`deployer ${onCc3.address}`);
  console.log(`  CC3     ${ethers.formatEther(ctc)} CTC`);
  console.log(`  Sepolia ${ethers.formatEther(eth)} ETH`);

  const d = load();
  d.network = { creditcoinChainId: cc3Id, sourceChainKey: SOURCE_CHAIN_KEY, sourceEvmChainId: sepId };
  d.deployer = onCc3.address;

  // ------------------------------------------------- source chain (Sepolia)
  if (d.workOracle && (await sepolia.getCode(d.workOracle)) !== '0x') {
    console.log(`\nSepolia: reusing WorkOracle at ${d.workOracle}`);
  } else if (eth > 0n) {
    console.log('\nSepolia (source chain):');
    d.workOracle = (await deploy('WorkOracle', onSepolia)).address;
    d.deployedAt = new Date().toISOString();
    save(d);
  } else {
    console.log('\nSepolia: SKIPPED, balance is zero');
  }

  // -------------------------------------------- settlement chain (CC3)
  const cc3Done = d.jobEscrow && (await cc3.getCode(d.jobEscrow)) !== '0x';
  if (cc3Done) {
    console.log(`Creditcoin: reusing JobEscrow at ${d.jobEscrow}`);
  } else if (ctc === 0n) {
    console.log('Creditcoin: SKIPPED, balance is zero');
  } else if (!d.workOracle) {
    console.log('Creditcoin: SKIPPED, the source oracle must exist first');
  } else {
    console.log('\nCreditcoin CC3 (settlement chain):');
    const usdc = await deploy('TestUSDC', onCc3);
    const registry = await deploy('SourceRegistry', onCc3);
    const escrow = await deploy('JobEscrow', onCc3, [
      usdc.address,
      registry.address,
      BOND_BPS,
      BOUNTY_BPS,
    ]);

    console.log('registering the Sepolia oracle as a trusted source...');
    const tx = await (registry.contract as any).registerSource(d.workOracle, {
      registered: false,
      kind: 0, // Attested
      chainKey: SOURCE_CHAIN_KEY,
      evmChainId: SOURCE_EVM_CHAIN_ID,
      topic0Completed: TOPIC_COMPLETED,
      topic0Failed: TOPIC_FAILED,
      completedJobIdTopic: 1,
      completedCriteriaTopic: 2,
      completedBuilderTopic: 3,
      failedJobIdTopic: 1,
      completedTopicCount: 4,
      failedTopicCount: 3,
      deliveryFromTopic: 0,
      deliveryToTopic: 0,
    });
    await tx.wait();
    console.log(`  registerSource(oracle)  ${tx.hash}`);

    const tx2 = await (registry.contract as any).registerSource(SEPOLIA_WETH, {
      registered: false,
      kind: 1, // Delivery
      chainKey: SOURCE_CHAIN_KEY,
      evmChainId: SOURCE_EVM_CHAIN_ID,
      topic0Completed: TOPIC_TRANSFER,
      topic0Failed: ethers.ZeroHash,
      completedJobIdTopic: 0,
      completedCriteriaTopic: 0,
      completedBuilderTopic: 0,
      failedJobIdTopic: 0,
      completedTopicCount: 3,
      failedTopicCount: 0,
      deliveryFromTopic: 1,
      deliveryToTopic: 2,
    });
    await tx2.wait();
    console.log(`  registerSource(WETH)    ${tx2.hash}`);
    d.sepoliaWeth = SEPOLIA_WETH;

    d.testUsdc = usdc.address;
    d.sourceRegistry = registry.address;
    d.jobEscrow = escrow.address;
    // Recorded so the console never scans below it. The CC3 RPC enforces a 10-second
    // query timeout and a wide eth_getLogs range hits it, so the floor is not cosmetic.
    d.deployBlock = (await (escrow.contract as any).deploymentTransaction()?.wait())?.blockNumber;
    d.deployedAt = new Date().toISOString();
    save(d);
  }

  save(d);
  const missing = [
    !d.workOracle && 'WorkOracle on Sepolia (fund the deployer with Sepolia ETH)',
    !d.jobEscrow && 'JobEscrow on CC3 (fund the deployer with CTC from the Discord faucet)',
  ].filter(Boolean);

  console.log(`\ndeployment record: ${PATH}`);
  if (missing.length) {
    console.log('\nINCOMPLETE. Still missing:');
    for (const m of missing) console.log(`  - ${m}`);
    console.log('\nRe-run `npm run deploy` once funded; existing contracts are reused.');
    process.exit(2);
  }
  console.log('\nComplete. Next: npm run e2e');
}

main().catch((e) => {
  console.error('DEPLOY FAILED:', e?.shortMessage ?? e?.message ?? e);
  process.exit(1);
});
