# Attestcoin Protocol Integration

How ProveOut uses Attestcoin, precisely enough to check.

---

## 1. What is used

| Component | Value | How it was verified |
|---|---|---|
| Block Prover Precompile | `0x0000000000000000000000000000000000000FD2` | docs → *Attestcoin Smart Contracts*; the Testnet page links its Blockscout entry; `NativeQueryVerifierLib.PRECOMPILE` in `@gluwa/asc-contracts` agrees; and we called it |
| Creditcoin CC3 Testnet | chain id `102031` | `eth_chainId` against `https://rpc.cc3-testnet.creditcoin.network` returned `0x18e8f` |
| Source chain | Ethereum Sepolia, **chain key `1`** | Attestcoin's chain key, *not* Sepolia's EVM chain id `11155111`. Confusing the two is the first mistake available. |
| Proof Builder | `https://prover.cc3-testnet.creditcoin.network` | used live |
| Base contract | `ASCBase` from `@gluwa/asc-contracts` | inherited by `JobEscrow` |
| Decoder | `EvmV1Decoder` from the same package | all-`internal` library, so it inlines; no external library linking needed |
| SDK | `@gluwa/usc-sdk@0.18.0` | `npm view` |

The precompile returns `0x` for `eth_getCode`. That is expected — it is a native
precompile with no EVM bytecode, and `NativeQueryVerifierLib.hasPrecompile()` special-cases
exactly this. Concluding "not deployed" from an empty code response would be wrong.

## 2. Which entry point, and why that one

`JobEscrow` inherits `ASCBase` and settles through the protocol's own
`execute(...)`, not through a bespoke wrapper:

```solidity
function execute(
    uint8 action,
    uint64 chainKey,
    uint64 blockHeight,
    bytes calldata encodedTransaction,
    bytes32 merkleRoot,
    INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
    bytes32 lowerEndpointDigest,
    bytes32[] calldata continuityRoots
) external returns (bool success);
```

`ASCBase` then, in this order:

1. computes `queryId = keccak256(chainKey, blockHeight, txIndex)`, where `txIndex` comes
   from `VERIFIER.calculateTxIndex(merkleProof)` — derived from the verified Merkle path,
   not supplied by the caller;
2. requires that query id to be unseen;
3. calls `VERIFIER.verifyAndEmit(chainKey, height, encodedTransaction, merkleProof, continuityProof)`
   and requires `true`;
4. marks the query id seen **before** dispatching (checks-effects-interactions);
5. calls our `_processAndEmitEvent(action, queryId, encodedTransaction)`.

**Continuity proof** (`lowerEndpointDigest` + `roots`) establishes that the block header
being used descends from an attested endpoint. **Merkle proof** (`root` + `siblings`)
establishes that this transaction is inside that block. Both are produced by the Proof
Builder service and passed through unmodified; ProveOut does not construct or reinterpret
either.

### A constraint worth stating plainly

`execute` is `external` and **not** `virtual`. Its signature is fixed by the protocol and
has no field for an application-level identifier. ProveOut therefore does **not** accept a
`jobId` argument. The job id is read out of the proved event itself.

This started as a limitation and ended as a security property: a caller cannot aim a valid
proof at the wrong job, because they never name a job at all. `action` (0 = release,
1 = challenge) is the only caller-supplied discriminator, matching how Gluwa's own
`ASCMinter` and `ASCLoanManager` use the field.

## 3. Why `receiptStatus == 1` is mandatory

This is the single most important line in the project.

The precompile proves that a transaction was **included in a block**. Inclusion is not
success. A transaction that reverted is still in the block, still in the transaction trie,
and still produces a perfectly valid inclusion proof.

Without this check, an attack is trivial: call `WorkCompleted` in a way that reverts, take
the resulting transaction, prove its inclusion completely honestly, and collect the escrow
for work that never happened.

```solidity
(uint64 provedChainId, EvmV1Decoder.ReceiptFields memory receipt) = _decodeProved(encodedTransaction);
if (receipt.receiptStatus != 1) revert ReceiptNotSuccessful(receipt.receiptStatus);
```

This mirrors Gluwa's reference `ASCMinter`, which does the same thing for the same reason.
Tested by `test_release_isRefused_whenReceiptStatusIsZero`.

## 4. Decoding, and the layout trap

`encodedTransaction` is **transaction + receipt data**, not the transaction alone. Its
layout, read out of the shipped `EvmV1Decoder` rather than assumed:

```
encodedTx = abi.encode(uint8 txType, bytes[] chunks)
  chunks[0] = abi.encode(nonce, gasLimit, from, toIsNull, to, value, data)
  chunks[1] = type-specific fields (chain id lives here for type 2)
  chunks[2] = abi.encode(receiptStatus, gasUsed, LogEntryTuple[], logsBloom)   // types 0-2
  chunks[3] = same, for types 3-4
```

Each `LogEntry` is `{ address address_; bytes32[] topics; bytes data; }`.

**The trap.** Indexed event parameters are in `topics[]`; non-indexed ones are in `data`.
Reading a field from the wrong place does not revert — it returns a well-formed wrong
value. ProveOut therefore stores the layout per source rather than hardcoding it:

```solidity
struct Source {
    bool registered;
    uint64 chainKey;
    uint64 evmChainId;
    bytes32 topic0Completed;
    bytes32 topic0Failed;
    uint8 completedJobIdTopic;      // 1
    uint8 completedCriteriaTopic;   // 2
    uint8 completedBuilderTopic;    // 3
    uint8 failedJobIdTopic;         // 1
    uint8 completedTopicCount;      // 4, checked exactly
    uint8 failedTopicCount;         // 3, checked exactly
}
```

Registering a new source chain is one transaction, not a code change.

For `WorkCompleted(bytes32 indexed jobId, bytes32 indexed criteriaHash, address indexed builder, bytes32 outputHash)`:
`topics[0]` is the signature, `topics[1..3]` are the three indexed fields, and `outputHash`
is the only thing in `data`.

Only transaction types 0 and 2 are accepted, because those are the two `EvmV1Decoder`
fully decodes. Type 3 and 4 are rejected with `UnsupportedTxType` rather than decoded on a
guess. A legacy transaction with a pre-EIP-155 `v` of 27 is also rejected: it carries no
chain id, so it cannot be pinned to a chain.

## 5. Replay protection — a documented deviation

The original design note called for a nullifier of `keccak256(chainId, txHash, logIndex)`.
We did not build it. `ASCBase` already refuses a repeated
`keccak256(chainKey, blockHeight, txIndex)`, and that value is **better sourced**: the
transaction index is derived by the precompile from the verified Merkle path, while a
caller-supplied `txHash` is caller-supplied. A transaction index is unique within a block,
so the two are equivalent for uniqueness.

Shipping a second, weaker nullifier beside the protocol's would have been decoration. We
test the protocol's behaviour as if it were ours — `Replay.t.sol` — because a dependency's
guarantee is only a guarantee while something checks it.

## 6. Chain binding, and why the emitter address is not enough

The registry is keyed by emitter address, which is good: that address comes from inside the
proved receipt and cannot be chosen by the caller.

But an address is not unique across chains. Identical bytecode deployed from an identical
nonce lands on the identical address on every EVM chain, and **CC3 Testnet attests both
Ethereum Sepolia (chain key 1) and Ethereum Mainnet (chain key 3)**. An attacker who
redeploys the oracle on the other attested chain would otherwise be able to emit anything
they liked and have it accepted.

So the escrow also decodes the proved transaction's **own chain id** and requires it to
match the chain that emitter was registered on:

```solidity
if (src.evmChainId != provedChainId) revert SourceChainMismatch(src.evmChainId, provedChainId);
```

Tested by `test_release_isRefused_whenProvedChainIdIsNotTheRegisteredChain`.

## 7. Attestation latency

Attestcoin lags the source chain head on purpose, so that a source-chain reorg cannot be
attested into permanence. Measured on CC3 Testnet during this build: latest attested
Sepolia height `11692700` against a Sepolia head of `11692738` — about 38 blocks, matching
the documented ~8–10 minutes.

ProveOut does not try to hide this. `deadline` on a job must be set with the attestation
delay in mind, and the relayer's `waitUntilHeightAttested` call is where the time goes.
Any system claiming instant cross-chain settlement on this protocol is not using it
correctly.

## 8. Two corrections to the documentation

Reported because both cost real time, and both are worth fixing upstream.

1. **`merkle-proving-and-transaction-inclusion.md` reads as though only the transaction is
   proved**, with no mention of receipts, logs or status. Taken alone it implies log-based
   readability is impossible. The fuller pages and the shipped `EvmV1Decoder` both make
   clear that `encodedTransaction` carries transaction **and** receipt data including
   `receiptStatus` and the full log array.

2. **The `hello-bridge` tutorial's example transaction hash
   (`0x87c97c77…`) returns HTTP 404 from the Proof Builder.** Its block has aged out of the
   service cache. Any transaction in a recently attested block works; the tutorial reads as
   though that specific hash is expected to keep working.

## 9. Reproducing the integration without a wallet

`verify()` on the precompile is `view`, so `eth_call` exercises the real verification path
against real attestation state at no cost:

```bash
npx tsx spikes/spike1_prove.ts 0x<any recent Sepolia tx hash>
```

Output on a real run is in [`../BUILD_LOG.md`](../BUILD_LOG.md).
