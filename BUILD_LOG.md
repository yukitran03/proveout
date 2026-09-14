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

## Step 3 — deploy and three real transactions — **DONE**

Both faucets landed (Sepolia first, CC3 about half an hour later), so `npm run deploy` was
built to deploy per chain and reuse whatever already exists rather than refusing to do the
half it could.

| Contract | Chain | Address |
|---|---|---|
| `JobEscrow` | CC3 Testnet | `0x6Ecf0f01DDE2b1872E6EA131c41De85e6a285BB6` (block 5480951) |
| `SourceRegistry` | CC3 Testnet | `0x5995bdC12087884B5766433c59eb42b8EbB3C50D` |
| `TestUSDC` | CC3 Testnet | `0xD40002aA8a8faDd14723b90690051a368232654e` |
| `WorkOracle` | Sepolia | `0xD40002aA8a8faDd14723b90690051a368232654e` |

**The two addresses above are identical, and that is not a typo.** The first contract this
deployer created on Sepolia and the first it created on Creditcoin came from the same
address at the same nonce, so CREATE put them at the same place on both chains. This is
exactly the collision gate G2b exists to reject, demonstrated by accident on the first
deployment. Worth keeping in the deck.

### The three transactions, verified independently after the fact

```
release    status=1 block=5480996 from=0x3Ef9…019c  logs=3  gas=306250
challenge  status=1 block=5481038 from=0xA035…92Ea  logs=4  gas=307888
replay     status=0 block=5481039 from=0x3Ef9…019c  logs=0  gas=212170
```

1. **Release** — `0x9a3c9b1d0a327cff81ba85f3456abfcf0ee810a1a8a69f8e2451665b9a2c1874`
   Proof of `WorkCompleted` on Sepolia block 11696158, txIndex 72, 7 merkle siblings,
   3 continuity roots. Builder received 1200 tUSDC (1000 payout + 200 bond returned).
2. **Challenge** — `0x6713f5e66d54554df8bf2603221300a890ae32bad8aa60de33015c92712a8966`
   Submitted **from `0xA0356B8011B63990978f2a7CCc389c3769d092Ea`**, which is neither the
   buyer nor the builder. Buyer refunded 1100, challenger paid a 100 tUSDC bounty out of
   the builder's bond. This is the project's whole thesis, on chain.
3. **Replay blocked** — `0xc4738c2976693c67365a8662923dd30e2c7dbc3d8048014ebd972bdd51a92836`
   Resubmitting proof #1 reverted with `Query already processed`. Status 0 on chain.

Escrow afterwards: `totalIn = totalOut = 2400000000` (2400 tUSDC), `vaultSolvent() = true`.

Attestation waits were 7–9 minutes each, matching the documented behaviour.

## Step 4 — web — **DONE**

Live: https://proveout.vercel.app

The console reads chain logs at request time. No indexer, no cache, no fixtures. Verified
against the deployment: it renders the two real jobs with `Released` and `Refunded`
badges and the vault invariant as `HOLDS`.

### Two real bugs caught before they shipped

1. **The console would have failed in production every time.** It scanned a
   200,000-block `eth_getLogs` range. The CC3 public RPC enforces a 10-second query
   timeout: measured, 20,000 blocks takes 6.5s and 200,000 fails outright. It now walks
   backwards in 5,000-block windows (about 0.6s each) from a recorded deployment floor,
   and a slow window degrades that window instead of blanking the page.

2. **`web/lib/` had never been committed.** `.gitignore` carried `lib/` for Foundry's
   dependency directory at the root, but an unanchored directory pattern matches at every
   depth. The console's entire chain-reading module was missing from the repository — it
   built here and would have failed for anyone who cloned it, including a judge. Anchored
   to `/lib/`. Verified by cloning the repo fresh and checking the file is present.

   The same bug would have broken the Vercel build for a second reason: Vercel does not
   upload gitignored `.env` files, so the deployed console would have had no contract
   address and rendered empty **without erroring**. Addresses now also go into a committed
   `web/lib/deployment.json`, still generated from the deployment record.

### On not cloning the UI repos

The plan named three repos to clone for the front end. All three are **Sui/Move** projects
and none has a `package.json` at its root. Retrofitting a Sui dApp onto an EVM escrow
would have cost more than it saved, so the layout ideas were taken — stepper console, hero
with three steps, table with status badges and truncated hashes — and the code is original.

## Step 5 — docs — **DONE**

`README.md`, `docs/attestcoin-integration.md`, `docs/technical-spec.md`,
`docs/threat-model.md`, and this file.

Every address and transaction hash in the README is **generated** by `npm run finalize`
from `deployments/cc3-testnet.json`. Nothing is typed by hand, so a redeployment cannot
leave a stale address behind in the docs — the failure the plan specifically warned about.


## Final hour — deck, video, submission text

### Deck

`deck/slides.html`, twelve slides at 1280x720, rendered to PDF by `node deck/render.mjs`
through Playwright and served from `web/public`. Live at
**https://proveout.vercel.app/ProveOut-deck.pdf** (verified 200, `application/pdf`, 440 KB).

Every figure on it is generated from the deployment record and the demo run. Nothing on a slide was typed from memory, which is the only way a deck
survives a redeploy without quietly going stale.

### Video

Recorded with Playwright in one continuous page context, so it needed no ffmpeg to stitch,
and captioned with a large overlay injected before each scene rather than narrated. A caption
track costs nothing to re-record when a number changes; a voice track does not.

Live at **https://proveout.vercel.app/demo.webm**.

Eight scenes: the thesis, the live console, all four demo transactions on their explorers with
the challenge held longest, a real proof run live on `/verify`, and the limitations card.


### One deliberate subtraction

The delivery-source work from earlier in the session was **stashed rather than committed**. It
adds a second kind of acceptance criterion: an on-chain transfer proved from an ordinary
third-party token, which removes the source-side trust assumption instead of narrowing it. It
is good work and it passed at 118 tests.

Its contracts were never deployed, because doing so needed three more attestation waits and
the window had closed. A repository whose Solidity does not match its deployed bytecode is
worse than one without the feature: it invites a judge to diff them and find a mismatch nobody
explained. So the repo was pinned back to exactly what is on chain, 97 tests, and the feature
waits for a run that can finish.

```
git stash list   # delivery-source: real third-party token as acceptance criterion
```

## After the deck: the source-side trust assumption, removed

The delivery e2e finished with time left, so the submission moved to it rather than shipping
the safer earlier run.

A job can now take an **ordinary ERC-20 as its acceptance criterion**. The builder must move at
least N tokens to a named beneficiary, and the token's own `Transfer` log is the proof.
Transaction 03 of the demo settles against canonical Sepolia WETH
(`0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`, verified on chain before it was written into the
deploy script: name "Wrapped Ether", 3,124 bytes of code). No oracle, no reporter and no
privileged caller is anywhere in that path, and nobody can emit that Transfer without actually
moving the tokens.

This answers the sharpest question the project had left, which was why we sourced facts from a
contract we wrote instead of from protocols that already exist. For an outcome that is itself
on-chain, we now do.

Both kinds stay, because they answer different questions. An attested job can express a
criterion that has no on-chain form. A delivery job removes the source-side trust assumption
rather than narrowing it. The site, the deck and the threat model each say which is which
instead of implying nothing is trusted.

`Transfer` carries no job id, so a delivery job reserves its route at creation: the triple of
token, sender and recipient. Exactly one job can ever match a given log, and an ordinary token's
unrelated transfers are skipped rather than reverting somebody else's settlement.

118 tests, and the repository matches the deployed bytecode again. The two were briefly out of
step while the earlier run was the live one, which is recorded above rather than tidied away.

## Logo

A stamp mark: one form whose negative space reads as a check or a strike depending on which arms
you follow, which is the product in a single shape.

Three variants rather than one file, because they have different jobs.

| File | Job |
|---|---|
| `web/public/mark.svg` | drawn in `currentColor`, so it inherits the theme and needs no second copy |
| `web/app/icon.svg` | states its colour with a `prefers-color-scheme` query, because a browser tab has no CSS to inherit from |
| `docs/logo-lockup.svg` | keeps its own dark ground, so it survives both GitHub themes in the README |


## Still open

- **Vercel token must be rotated.** It travelled through a chat transcript and sits in the
  plan HTML file. Revoke and reissue.
- **Contract source is not verified on Blockscout.** Worth doing before submission if the
  explorer supports it for CC3; if it does not, say so in the README rather than leaving it
  unexplained.
- **Repo is private.** It must be switched to public before the DoraHacks entry is judged.
- **Deck PDF and demo video** are not built. The plan assigns both to the owner.
