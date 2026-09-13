import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './env.js';

/**
 * Reads ABIs and bytecode straight out of the Foundry build. No hand-maintained ABI
 * copies: a copy drifts silently the first time a signature changes, and a drifted ABI
 * decodes garbage instead of failing.
 */
export function artifact(name: string): { abi: any[]; bytecode: string } {
  const path = join(ROOT, 'contracts', 'out', `${name}.sol`, `${name}.json`);
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  return { abi: raw.abi, bytecode: raw.bytecode.object };
}

/** Exact `execute` fragment of ASCBase, as Foundry emits it. */
export const EXECUTE_SIGNATURE =
  'execute(uint8,uint64,uint64,bytes,bytes32,tuple(bytes32,bool)[],bytes32,bytes32[])';

export const ACTION_RELEASE = 0;
export const ACTION_CHALLENGE = 1;
