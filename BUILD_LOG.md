# BUILD_LOG — ProveOut

Everything below was run, not assumed. Numbers are copied from real output.
Machine: HP EliteBook 845 G11 (Ryzen 7 8840U, 64 GB). Started 2026-09-13.

---

## Step 0 — the death gate (budget: 90 min) — **PASSED**

The plan said: verify every address yourself, prove one Sepolia transaction on CC3, print
its `receiptStatus`. Done, and passed without needing a funded wallet — see "the trick" below.

### Facts verified from the source, replacing the plan's assumptions

| Thing | Plan said | Verified value | How |
|---|---|---|---|
| Block Prover precompile | `0x0FD2`, unverified | `0x0000000000000000000000000000000000000FD2` — **correct** | docs.attestcoin.org → Attestcoin Smart Contracts; Testnet page links its live Blockscout page; `NativeQueryVerifierLib.PRECOMPILE` in the shipped package agrees |
| CC3 Testnet chain id | `102031` | `0x18e8f` = **102031** — correct | `eth_chainId` against the live RPC |
| CC3 Testnet RPC | not given | `https://rpc.cc3-testnet.creditcoin.network` | `bridge/.env.example` in gluwa/usc-testnet-bridge-examples |
| Sepolia chain key | not given | **1** (≠ its EVM chain id 11155111) | same file, plus the Testnet docs page |
| Proof builder | not given | `https://prover.cc3-testnet.creditcoin.network` | same file |
| SDK | not given | `@gluwa/usc-sdk@0.18.0` | `npm view` |
| Contract package | not given | `@gluwa/asc-contracts` (`ASCBase`, `EvmV1Decoder`) | read from `node_modules`, not from docs |
| Explorer | not given | `https://creditcoin-testnet.blockscout.com` | Testnet docs page |
| Toolchain | not given | solc 0.8.30, `via_ir = true`, `evm_version = "shanghai"`, optimizer 200 | copied from the reference examples' own `foundry.toml`, which is known to deploy on CC3 |

`NativeQueryVerifierLib.isCreditcoinChainId` accepts 102030/102031/102032, independently
confirming 102031.

### One thing the plan got wrong, and one thing it got right

**Right, and it is the most important line in the project.** The plan insisted on a
`receiptStatus == 1` gate. That is not a nice-to-have we invented — it is the pattern
Gluwa's own reference `ASCMinter.sol` uses verbatim:

```solidity
EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
require(receipt.receiptStatus == 1, "Transaction did not succeed");
```

**A scare that turned out to be wrong.** Mid-verification, `merkle-proving-and-transaction-
inclusion.md` reads as though the proof covers only the transaction, which would mean no
logs and no receipt status — and would have killed the whole design. It does not. The
fuller pages and the shipped decoder both confirm `encodedTransaction` carries
*transaction + receipt data*, including `receiptStatus` and the full log array. Recorded
here because the doc page alone is misleading, and that is worth telling the judges.

### Spikes

`spikes/spike1_prove.ts` — proves a real Sepolia transaction on CC3 and decodes it.

**The trick that saved the gate:** `verify()` on the precompile is `view`. Calling it
through `eth_call` verifies a real proof against real on-chain attestation state while
costing nothing and needing no funded wallet. The faucet is only needed to *write*.

Run:

```
npx tsx spikes/spike1_prove.ts 0x949890fc606893cf7c209845ab5105f94d04fde0f0c245e5de1e57f5eb694c39
```

Real output:

```
CC3 chainId  : 102031
Latest attested Sepolia height on CC3: 11692700
  headerNumber : 11689820
  txIndex      : 1
  merkle sibs  : 7
  continuity   : 81 roots
  txBytes len  : 3104 bytes
PRECOMPILE verify  => true
computeTxIndex     => 1n
txType        : 2
RECEIPTSTATUS : 1 (SUCCESS)
gasUsed       : 121153
logs          : 5
  [0] emitter=0x899d225d779F41fA1aB422aB1b8A9408296dD5C6
      topic0=0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
      topic1=0x00000000000000000000000059862b22b52dba1c60385b8def66f5cbe4ab824b
      topic2=0x000000000000000000000000747e4e229ac88339353d039f0c4a635b61c65a28
      data=0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
*** DEATH GATE PASSED ***
```

That output is the whole thesis of the project working: a foreign chain's event, its
emitter address, its indexed topics and its receipt status, all readable inside a
Creditcoin call, with no operator in the path.

The tutorial's own example hash (`0x87c97c…`) returns **404** from the proof builder — its
block has aged out of the service cache. Any transaction in a recent attested block works.

### Attested-height lag

Latest attested Sepolia height was 11692700 while the Sepolia head was 11692738 —
about 38 blocks, matching the documented ~8–10 minute attestation delay. Budget for it in
the e2e run: each of the three demo transactions waits out one attestation.

---

## Step 1 — contracts — **DONE**

`forge build` clean on solc 0.8.30.

Four contracts, as specified: `TestUSDC`, `SourceRegistry`, `WorkOracle` (Sepolia),
`JobEscrow` (CC3).

### Three design changes forced by the real API

The plan was written against an imagined interface. The shipped one differs in ways that
matter, and the changes make the design *stronger*, not weaker:

1. **`release(jobId, proof)` cannot exist.** `ASCBase.execute()` is `external` and not
   `virtual`; its signature is fixed by the protocol and carries no room for a `jobId`.
   So the job id is not passed in — it is **read out of the proved event itself**. The
   caller cannot point a valid proof at the wrong job, because they no longer name the job
   at all. `action` (0 = release, 1 = challenge) is the only discriminator, exactly as
   Gluwa's own `ASCMinter`/`ASCLoanManager` use it.

2. **The nullifier is the protocol's, not ours.** The plan specified
   `keccak256(chainId, txHash, logIndex)`. `ASCBase` already refuses a repeated
   `keccak256(chainKey, blockHeight, txIndex)`, where `txIndex` is derived by the
   precompile from the verified Merkle path rather than supplied by the caller. That is
   equivalent for uniqueness and better sourced. Shipping a second, weaker nullifier beside
   it would have been decoration. Tested as ours in `Replay.t.sol` regardless.

3. **Gate 2 gained a second half.** The registry is keyed by emitter address, which comes
   from inside the proved receipt and so cannot be chosen by the caller. But an address is
   not unique across chains: identical bytecode from an identical nonce deploys to the same
   address on every EVM chain, and CC3 Testnet attests both Sepolia and Ethereum mainnet.
   So the escrow also decodes the proved transaction's **own chain id** and requires it to
   match the chain the emitter was registered on. Without this, an attacker redeploys the
   oracle on the other attested chain and emits whatever they like.

### The six gates, as built

| Gate | Enforced by | Test |
|---|---|---|
| G1 receipt status == 1 | `ReceiptNotSuccessful` | `test_release_isRefused_whenReceiptStatusIsZero` |
| G2 emitter registered | `SourceRegistry.getSource` | `test_release_isRefused_whenEmitterIsNotRegistered` |
| G2b proved chain id matches | `SourceChainMismatch` | `test_release_isRefused_whenProvedChainIdIsNotTheRegisteredChain` |
| G3 exact topic0 + topic count | registry layout | `test_release_isRefused_whenTopic0IsNotWorkCompleted` |
| G4 fields read from stored positions | registry layout | `test_release_isRefused_whenCriteriaHashDiffersFromTheFrozenOne` |
| G5 query id unseen | `ASCBase` | `test_replay_isRefused_whenTheSameProofIsSubmittedTwice` |
| G6 within deadline | `DeadlinePassed` | `test_release_isRefused_afterDeadline` |

---

## Step 2 — tests — **DONE**

```
Ran 4 test suites: 46 tests passed, 0 failed, 0 skipped (46 total tests)
InvariantTest invariants (runs: 64, calls: 6144, reverts: 0)
  [PASS] invariant_vaultIsAlwaysSolvent
  [PASS] invariant_payoutsNeverExceedDeposits
```

46 against a required minimum of 25. The invariant handler includes a `donate()` action
that pushes unsolicited tokens into the vault, which is what proves the balance rule has to
be an inequality: with `==` a stranger sending one micro-unit would wedge every escrow.

The precompile is mocked for unit tests so they run offline. **That is not sufficient on
its own** and the submission does not pretend otherwise — see Step 3.

---

## Step 3 — deploy and three real transactions — **BLOCKED ON FAUCET**

Not started, and cannot be started from this machine. Both faucets require a human:

- **Creditcoin CC3**: Discord-only (`/faucet address:`), 100 CTC per 24 h.
- **Sepolia**: Google Cloud web3 faucet, needs a Google sign-in.

Everything else is ready and waiting. Sprint wallet generated locally:

```
0x3Ef919342928307ABdCc9ec702f6f3c4f34f019c
```

Private key at `~/.config/hackathon-sprint/proveout.env` (chmod 600, outside every repo).
Never written into this repository.

No Infura key is needed after all: `https://ethereum-sepolia-rpc.publicnode.com` serves the
Sepolia reads this project makes, which removes one of the plan's human dependencies.

Nothing in the README claims a deployment, a transaction hash or an on-chain number until
this step actually runs.
