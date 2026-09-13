import { NextResponse } from 'next/server';
import { ethers } from 'ethers';
import { blockProver, chainInfo, proofProvider } from '@gluwa/usc-sdk';

import { CC3_RPC, SOURCE_CHAIN_KEY } from '../../../lib/chain';

export const dynamic = 'force-dynamic';
export const maxDuration = 60;

const PROOF_BUILDER_URL = 'https://prover.cc3-testnet.creditcoin.network';

const abi = ethers.AbiCoder.defaultAbiCoder();

/**
 * Decodes the proved bytes using the layout of the shipped EvmV1Decoder:
 *
 *   encodedTx = abi.encode(uint8 txType, bytes[] chunks)
 *   chunks[2] (types 0-2) or chunks[3] (types 3-4) is the receipt:
 *   abi.encode(uint8 receiptStatus, uint64 gasUsed, LogEntryTuple[] logs, bytes logsBloom)
 */
function decodeReceipt(txBytes: string) {
  const [txType, chunks] = abi.decode(['uint8', 'bytes[]'], txBytes);
  const receiptIdx = Number(txType) <= 2 ? 2 : 3;
  const [status, gasUsed, logs] = abi.decode(
    ['uint8', 'uint64', 'tuple(address,bytes32[],bytes)[]', 'bytes'],
    chunks[receiptIdx],
  );
  return {
    txType: Number(txType),
    receiptStatus: Number(status),
    gasUsed: gasUsed.toString(),
    logs: (logs as any[]).map((l) => ({
      emitter: l[0] as string,
      topics: (l[1] as string[]).map(String),
      data: l[2] as string,
    })),
  };
}

export async function POST(request: Request) {
  let txHash: string;
  try {
    ({ txHash } = await request.json());
  } catch {
    return NextResponse.json({ error: 'Send a JSON body with a txHash.' }, { status: 400 });
  }

  if (typeof txHash !== 'string' || !/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
    return NextResponse.json(
      { error: 'That is not a transaction hash. Expected 0x followed by 64 hex characters.' },
      { status: 400 },
    );
  }

  const cc3 = new ethers.JsonRpcProvider(CC3_RPC);

  try {
    const attested = await new chainInfo.PrecompileChainInfoProvider(cc3)
      .getLatestAttestedHeightAndHash(SOURCE_CHAIN_KEY)
      .catch(() => null);

    const result = await new proofProvider.service.ProofBuilder(
      SOURCE_CHAIN_KEY,
      PROOF_BUILDER_URL,
    ).getProof(txHash);

    if (!result.success || !result.data) {
      return NextResponse.json(
        {
          error:
            'The proof builder has no proof for that transaction yet. Either it is not on Sepolia, ' +
            'or its block has not been attested on Creditcoin. Attestation deliberately lags the ' +
            'source chain by roughly eight to ten minutes so a reorg cannot be attested into permanence.',
          latestAttestedHeight: attested ? Number(attested.height) : null,
        },
        { status: 404 },
      );
    }

    const p = result.data;

    // The real call. `verify` is a view function on the precompile, so this exercises the
    // actual verification path against real attestation state without spending anything.
    const verified = await new blockProver.PrecompileBlockProver(cc3).verifySingle(
      p.chainKey,
      p.headerNumber,
      p.txBytes,
      p.merkleProof,
      p.continuityProof,
    );

    const receipt = decodeReceipt(p.txBytes);

    return NextResponse.json({
      txHash,
      verified,
      precompile: '0x0000000000000000000000000000000000000FD2',
      chainKey: p.chainKey,
      headerNumber: p.headerNumber,
      txIndex: p.txIndex,
      merkleSiblings: p.merkleProof.siblings.length,
      continuityRoots: p.continuityProof.roots.length,
      provedBytes: (p.txBytes.length - 2) / 2,
      latestAttestedHeight: attested ? Number(attested.height) : null,
      ...receipt,
    });
  } catch (e: any) {
    return NextResponse.json(
      { error: e?.shortMessage ?? e?.message ?? 'Verification failed.' },
      { status: 500 },
    );
  }
}
