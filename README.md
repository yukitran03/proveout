# ProveOut

**Money moves when the work is proved — and anyone can prove it failed.**

A job escrow on Creditcoin CC3 that releases or refunds based on an event that happened on
Ethereum Sepolia, proved on-chain by the Attestcoin Block Prover precompile inside a single
Creditcoin transaction. No oracle operator, no arbiter, no human pressing approve.

---

## Status

| | |
|---|---|
| Contracts | built, `forge build` clean on solc 0.8.30 |
| Tests | **97 passing, 0 failing**, including a 6144-call invariant run |
| Attestcoin integration | **verified live** against the real precompile on CC3 Testnet — see below |
| Deployment + demo transactions | see the block below |

**[Deck (PDF)](https://proveout.vercel.app/ProveOut-deck.pdf)** · **[Demo video](https://proveout.vercel.app/demo.webm)** · **[Verify a proof, no wallet needed](https://proveout.vercel.app/verify)** · **[Submission text](docs/SUBMISSION.md)**

This table is the honest state of the repository. No contract address or transaction hash
appears anywhere in this repo until it has actually been produced — nothing is placeheld
with a number that was never run.

<!-- BEGIN:DEPLOYMENT -->
## Deployed

**Live console:** https://proveout.vercel.app  
**Repository:** https://github.com/yukitran03/proveout

| Contract | Chain | Address |
|---|---|---|
| `JobEscrow` | Creditcoin CC3 Testnet | [`0x9940f7659490E3e3dA3294397951eE84C3B28db4`](https://creditcoin-testnet.blockscout.com/address/0x9940f7659490E3e3dA3294397951eE84C3B28db4) |
| `SourceRegistry` | Creditcoin CC3 Testnet | [`0xb5f9F7728b24D8173B798b78df92c8Dab21909f3`](https://creditcoin-testnet.blockscout.com/address/0xb5f9F7728b24D8173B798b78df92c8Dab21909f3) |
| `TestUSDC` | Creditcoin CC3 Testnet | [`0xb257A8aAE29BE4B7A80fbD192C089E233529Dd92`](https://creditcoin-testnet.blockscout.com/address/0xb257A8aAE29BE4B7A80fbD192C089E233529Dd92) |
| `WorkOracle` | Ethereum Sepolia | [`0x1e40b277AaB35D642c5F30A46276F46A6d3C11A9`](https://sepolia.etherscan.io/address/0x1e40b277AaB35D642c5F30A46276F46A6d3C11A9) |

### The 4 transactions

| # | What it proves | Source transaction (Sepolia) | Settlement (Creditcoin) |
|---|---|---|---|
| 1 | A proved `WorkCompleted` pays the builder 1,200 tUSDC | [`0xa81e6a2ee9b2...`](https://sepolia.etherscan.io/tx/0xa81e6a2ee9b23067781feed1c696f368e2f3fb520f428a5001edf3bb15bff218) | [`0x507ab15719e3...`](https://creditcoin-testnet.blockscout.com/tx/0x507ab15719e304cd117580bfebccf705c3788a574743e2c889544e3fba72397e) |
| 2 | A proved `WorkFailed`, submitted by [`0xA0356B80...`](https://creditcoin-testnet.blockscout.com/address/0xA0356B8011B63990978f2a7CCc389c3769d092Ea), **neither the buyer nor the builder**, refunds 1,100 tUSDC and pays that wallet a 100 tUSDC bounty | [`0xdec8b8526795...`](https://sepolia.etherscan.io/tx/0xdec8b852679599b396cdd83f8ae4b45392284d4ea3d648d5953bc6a14e954b92) | [`0x8f9575743aef...`](https://creditcoin-testnet.blockscout.com/tx/0x8f9575743aef5fb49db6570e9f7b57dec4c361afd1d580f2c81e1778e8a915ac) |
| 3 | Replaying proof #1 is refused on-chain (`execution reverted: "Query already processed"`) | | [`0x06dab25c8d72...`](https://creditcoin-testnet.blockscout.com/tx/0x06dab25c8d722886a110aa2be80b401819826552a65625ad1a7c93f60ca9c360) |
| 4 | The builder calls `reportCompleted` for their own job on the source chain and is refused there, before any proof can exist. `isReporter(builder)` is `false` | [`0xa1ac8a598953...`](https://sepolia.etherscan.io/tx/0xa1ac8a598953c14cd21bd3f2669eccc8ca7d632fe5a83d77c5629b0dec42c775) reverted | |

_Deployed 2026-09-13T18:37:35.191Z by `0x3Ef919342928307ABdCc9ec702f6f3c4f34f019c` on CC3 chain id 102031, source chain key 1, escrow from block 5482220._
<!-- END:DEPLOYMENT -->

### Check the integration yourself, without a wallet

The transactions above are the system running. If you would rather not take them on trust,
`spikes/spike1_prove.ts` calls the live Block Prover precompile at
`0x0000000000000000000000000000000000000FD2` on Creditcoin CC3 Testnet with a real proof of
a real Ethereum Sepolia transaction, and reads its receipt back:

```
CC3 chainId  : 102031
Latest attested Sepolia height on CC3: 11692700
  headerNumber : 11689820   txIndex : 1
  merkle sibs  : 7          continuity : 81 roots
PRECOMPILE verify  => true
RECEIPTSTATUS : 1 (SUCCESS)
logs          : 5
  [0] emitter=0x899d225d779F41fA1aB422aB1b8A9408296dD5C6
      topic0=0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
```

Reproduce it yourself, with no wallet and no funds:

```bash
npm install
npx tsx spikes/spike1_prove.ts   # pass any recent Sepolia tx hash
```

It works unfunded because the precompile's `verify()` is `view`, so `eth_call` exercises
the real verification path for free. That is the whole mechanism this project is built on,
running, today.

---

## What it does

A buyer locks USDC on Creditcoin against a job whose acceptance criteria are hashed and
frozen before any work starts. The builder stakes a bond. Then exactly one of three things
ends the escrow:

| Path | Who can trigger it | What must be proved |
|---|---|---|
| **Release** | anyone | `WorkCompleted` was emitted by the registered oracle on Sepolia, in a transaction that succeeded |
| **Challenge** | **anyone**, and they are paid for it | `WorkFailed` was emitted for this job — buyer is refunded, the challenger takes a bounty out of the builder's bond |
| **Refund** | anyone, after the deadline | nothing; it is the default exit |

### Why the challenge path is the point

The usual shape of a cross-chain reputation or settlement system is: *the party who
benefits watches for their own good news and submits it.* A worker sees the repayment and
posts it. A builder sees their own success and posts it.

Nobody posts their own failure. A design like that does not need to censor bad news — bad
news simply never gets submitted, because the only party watching has no reason to.

ProveOut pays strangers to submit it. `challengeFailure` is callable by any address on
earth, and the bounty comes out of the bond of the party that failed. The evidence stops
being something the beneficiary curates.

---

## What this does NOT do

Read this before deciding how much to believe the rest.

- **The source oracle is trusted within its own scope.** Whoever holds a reporter role on
  `WorkOracle` decides what is provable. ProveOut narrows trust to one named contract with a
  named reporter set, and a builder cannot certify their own work. It does not eliminate
  trust in the source, and no proof system can.
- **Attestcoin proves inclusion, not exclusion.** It can prove a transaction happened. It
  cannot prove no other transaction happened. So ProveOut does **not** make hiding a
  failure impossible — it makes hiding one *detectable and expensive*. That is the entire
  promise of the challenge mechanism, and it is not more than that.
- **`TestUSDC` is not USDC.** It is a six-decimal demo token with an open mint and no value.
- **Testnet only. Unaudited.** Nothing here has had a security review.
- **The bond ratio is a demo parameter**, not an economic result. Whether 20% of the job
  value is enough to make challenging worthwhile depends on real bounty economics this
  project has not modelled.
- **Only transaction types 0 and 2 are accepted.** The shipped `EvmV1Decoder` fully decodes
  those; anything else is rejected loudly rather than decoded on a guess.
- **The relayer is not trusted, but it is also not redundant yet.** Anyone can submit
  proofs, but nobody currently does it automatically except our one worker process.

---

## Architecture

```
Ethereum Sepolia (source)              Creditcoin CC3 (settlement)
─────────────────────────              ───────────────────────────
WorkOracle.sol                         SourceRegistry.sol
 ├ WorkCompleted(jobId, criteriaHash,   └ emitter → {chainKey, evmChainId,
 │               builder, outputHash)                topic0s, topic positions}
 └ WorkFailed(jobId, reason)
                                       JobEscrow.sol  is ASCBase
      │                                 ├ createJob / postBond / fundJob
      │  relayer: wait for the block    ├ execute(action=0) → release
      │  to be attested, fetch the      ├ execute(action=1) → challenge, ANY caller
      └─ proof, submit ────────────────▶├ refund() after the deadline
                                        └ replay guard: ASCBase query id
                                       TestUSDC.sol
```

Settlement is **synchronous**: verification and payout happen in one Creditcoin
transaction. There is no message queue and no second confirmation step.

### The six gates on the settlement path

| | Check | Why it exists |
|---|---|---|
| G1 | `receiptStatus == 1` | The precompile proves a transaction was *in a block*. A reverted transaction is in the block too. Without this, a builder sends a `WorkCompleted` call that reverts, proves the inclusion honestly, and gets paid. |
| G2 | emitter is in `SourceRegistry` | Otherwise anyone deploys their own oracle, emits a perfect event, proves it honestly, and drains every escrow. |
| G2b | proved tx's own chain id matches | Identical bytecode from an identical nonce lands on the same address on every EVM chain, and CC3 attests more than one. The address alone does not pin down the chain. |
| G3 | exact `topic0` and topic count | Stops a different event of the same shape from settling a job. |
| G4 | fields read from registered positions | Indexed parameters live in `topics[]`, not `data`. Reading the wrong slot returns plausible garbage, not an error. |
| G5 | query id unseen | One proof settles at most once. Enforced by `ASCBase` using an index the precompile derives from the verified Merkle path, not from caller input. |
| G6 | `block.timestamp <= deadline` | Release and refund windows are disjoint, so the builder and the buyer never race on transaction ordering. |

`challengeFailure` reuses G1–G5 and deliberately **skips G6**: a failure stays provable
forever, or hiding one until the clock ran out would be a winning strategy.

---

## Tests

```
Ran 6 test suites: 97 tests passed, 0 failed, 0 skipped
InvariantTest invariants (runs: 64, calls: 6144, reverts: 0)
  [PASS] invariant_vaultIsAlwaysSolvent
  [PASS] invariant_payoutsNeverExceedDeposits
```

```bash
npm run test
```

Tests are named as claims rather than chores. The ones that carry the most weight:

- `test_release_isRefused_whenReceiptStatusIsZero` — the inclusion-is-not-success gate
- `test_anyone_canForceRefund_withFailureProof` — the adversarial-evidence property
- `test_release_isRefused_whenProvedChainIdIsNotTheRegisteredChain` — cross-chain address collision
- `test_replay_isRefused_whenTheSameProofIsSubmittedTwice`
- `test_builder_cannotCertifyTheirOwnWork` — the source-side bypass that made every gate below it decorative
- `test_stranger_cannotBurnAnHonestBuildersBond`
- `test_releaseAndRefundWindows_neverOverlap`
- `test_escrow_hasNoAdminAbleToTouchUserFunds`

The precompile is mocked in unit tests so they run offline. A mock alone would not be
evidence of anything, which is why the live spike above exists and why the demo below runs
against the real precompile.

---

## Running it

```bash
npm install
npm run build:contracts
npm run test

# needs a funded wallet on both chains
npm run deploy      # WorkOracle → Sepolia; TestUSDC + Registry + Escrow → CC3
npm run e2e         # the three demo transactions
npm run worker      # optional: the relayer, watching Sepolia

npm run finalize    # write the deployment into the README and the web build
npm run deploy:web  # publish the console and move the stable alias onto it
```

`npm run e2e` produces three real transactions — a release, a challenge-refund submitted by
a wallet that is neither the buyer nor the builder, and a blocked replay — and writes them
to `deployments/e2e-results.json`. Run `npm run finalize` afterwards and every address
and hash in this README and on the site updates itself from that record, so a redeploy
cannot leave a stale one behind.

`npm run deploy:web` exists because Vercel gives each deployment its own hashed hostname
and does not move a project alias on its own. Publishing without re-aliasing leaves
`proveout.vercel.app`, which is the URL every link points at, serving the previous build.
It needs a Vercel token at `~/.config/hackathon-sprint/vercel.env`, outside the repository.

Each proof waits out a real attestation, roughly 8–10 minutes on Sepolia. That delay is
deliberate protocol behaviour, not slowness: it is what stops a source-chain reorg from
being attested into permanence.

## Docs

- [`docs/attestcoin-integration.md`](docs/attestcoin-integration.md) — exactly how the precompile is used
- [`docs/technical-spec.md`](docs/technical-spec.md)
- [`docs/threat-model.md`](docs/threat-model.md) — what each gate stops
- [`docs/deck-prompt.md`](docs/deck-prompt.md) — the full prompt for building the pitch deck, with every figure it is allowed to use
- [`docs/SUBMISSION.md`](docs/SUBMISSION.md) — the form text, ready to paste
- [`docs/FACTS.md`](docs/FACTS.md) — generated sheet of every current figure
- [`docs/logo-prompt.md`](docs/logo-prompt.md)
- [`docs/demo-video.md`](docs/demo-video.md) — shot list and spoken script for the demo video
- [`BUILD_LOG.md`](BUILD_LOG.md) — what was verified, what was assumed and turned out wrong

## License

Apache-2.0.
