import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/**
 * Secrets live OUTSIDE the repository, at ~/.config/hackathon-sprint/proveout.env
 * (chmod 600). `.env` in the repo root is honoured as a fallback for other machines,
 * and is gitignored. Nothing here ever writes a key back to disk inside ROOT.
 */
function loadDotEnv(path: string) {
  if (!existsSync(path)) return;
  for (const raw of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const key = line.slice(0, eq).trim();
    const value = line.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (!(key in process.env)) process.env[key] = value;
  }
}

loadDotEnv(join(homedir(), '.config', 'hackathon-sprint', 'proveout.env'));
loadDotEnv(join(ROOT, '.env'));

export function need(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env var ${key}. See .env.example.`);
  return v;
}

export const CC3_RPC = process.env.CREDITCOIN_RPC_URL ?? 'https://rpc.cc3-testnet.creditcoin.network';
export const SEPOLIA_RPC = process.env.SOURCE_CHAIN_RPC_URL ?? 'https://ethereum-sepolia-rpc.publicnode.com';
export const PROOF_BUILDER_URL =
  process.env.PROOF_BUILDER_URL ?? 'https://prover.cc3-testnet.creditcoin.network';
/** Attestcoin's key for Ethereum Sepolia on CC3 Testnet. Not its EVM chain id. */
export const SOURCE_CHAIN_KEY = Number(process.env.SOURCE_CHAIN_KEY ?? 1);
export const SOURCE_EVM_CHAIN_ID = Number(process.env.SOURCE_EVM_CHAIN_ID ?? 11_155_111);
export const CC3_CHAIN_ID = Number(process.env.CREDITCOIN_CHAIN_ID ?? 102_031);
export const EXPLORER = 'https://creditcoin-testnet.blockscout.com';
export const SEPOLIA_EXPLORER = 'https://sepolia.etherscan.io';

export type Deployment = {
  network: { creditcoinChainId: number; sourceChainKey: number; sourceEvmChainId: number };
  workOracle: string;
  testUsdc: string;
  sourceRegistry: string;
  jobEscrow: string;
  deployedAt: string;
  deployer: string;
};

const DEPLOY_PATH = join(ROOT, 'deployments', 'cc3-testnet.json');

export function readDeployment(): Deployment {
  if (!existsSync(DEPLOY_PATH)) {
    throw new Error(`No deployment found at ${DEPLOY_PATH}. Run: npm run deploy`);
  }
  return JSON.parse(readFileSync(DEPLOY_PATH, 'utf8')) as Deployment;
}

export function writeDeployment(d: Deployment) {
  mkdirSync(dirname(DEPLOY_PATH), { recursive: true });
  writeFileSync(DEPLOY_PATH, JSON.stringify(d, null, 2) + '\n');
  console.log(`deployment written to ${DEPLOY_PATH}`);
}
