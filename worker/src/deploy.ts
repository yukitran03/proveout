import { ContractFactory, ethers } from 'ethers';
import { artifact } from './artifacts.js';
import {
  CC3_CHAIN_ID,
  CC3_RPC,
  SEPOLIA_RPC,
  SOURCE_CHAIN_KEY,
  SOURCE_EVM_CHAIN_ID,
  need,
  writeDeployment,
} from './env.js';

const BOND_BPS = 2_000; // builder stakes 20% of the job amount
const BOUNTY_BPS = 5_000; // a successful challenger takes half of that bond

export const TOPIC_COMPLETED = ethers.id('WorkCompleted(bytes32,bytes32,address,bytes32)');
export const TOPIC_FAILED = ethers.id('WorkFailed(bytes32,bytes32)');

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
  if (sepId !== SOURCE_EVM_CHAIN_ID) throw new Error(`expected source chain ${SOURCE_EVM_CHAIN_ID}, got ${sepId}`);

  const ctc = await cc3.getBalance(onCc3.address);
  const eth = await sepolia.getBalance(onSepolia.address);
  console.log(`deployer ${onCc3.address}`);
  console.log(`  CC3 balance     ${ethers.formatEther(ctc)} CTC`);
  console.log(`  Sepolia balance ${ethers.formatEther(eth)} ETH`);
  if (ctc === 0n) throw new Error('CC3 balance is zero — fund from the Creditcoin Discord faucet');
  if (eth === 0n) throw new Error('Sepolia balance is zero — fund from a Sepolia faucet');

  console.log('\nSepolia (source chain):');
  const oracle = await deploy('WorkOracle', onSepolia);

  console.log('\nCreditcoin CC3 (settlement chain):');
  const usdc = await deploy('TestUSDC', onCc3);
  const registry = await deploy('SourceRegistry', onCc3);
  const escrow = await deploy('JobEscrow', onCc3, [usdc.address, registry.address, BOND_BPS, BOUNTY_BPS]);

  console.log('\nregistering the Sepolia oracle as a trusted source...');
  const tx = await (registry.contract as any).registerSource(oracle.address, {
    registered: false,
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
  });
  await tx.wait();
  console.log(`  registerSource ${tx.hash}`);

  writeDeployment({
    network: { creditcoinChainId: cc3Id, sourceChainKey: SOURCE_CHAIN_KEY, sourceEvmChainId: sepId },
    workOracle: oracle.address,
    testUsdc: usdc.address,
    sourceRegistry: registry.address,
    jobEscrow: escrow.address,
    deployedAt: new Date().toISOString(),
    deployer: onCc3.address,
  });
}

main().catch((e) => {
  console.error('DEPLOY FAILED:', e?.shortMessage ?? e?.message ?? e);
  process.exit(1);
});
