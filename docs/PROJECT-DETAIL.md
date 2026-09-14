# Project Detail

**Money moves when the work is proved, and anyone can prove it failed.**

[Live app](https://proveout.vercel.app) · [Verify a proof yourself, no wallet](https://proveout.vercel.app/verify) · [Deck (PDF)](https://proveout.vercel.app/ProveOut-deck.pdf) · [Demo video](https://proveout.vercel.app/demo.webm) · [Repository](https://github.com/yukitran03/proveout)

---

## The problem

When an AI agent works across chains, there is no safe way to pay it. Pay first and the buyer
loses the money if the work never happens. Pay after and the agent has no guarantee it will
ever be paid.

Every existing answer inserts a third party to decide whether the work was done: an oracle
operator, an arbiter, or the platform itself. Someone, somewhere, presses a button.

## The hole nobody names

Cross-chain systems that settle on proof mostly work. But there is a gap in how they are
usually built, and it does not get said out loud.

**The party who benefits is the one who submits the evidence.** A worker sees the repayment
and posts it. A builder finishes the job and posts the receipt.

Nobody posts their own failure.

Such a system does not need to censor bad news. Bad news simply never arrives, because the
only party watching has no reason to send it, and the escrow quietly waits out its timeout.

**ProveOut pays strangers to submit it.** `challengeFailure` is callable by any address on
earth, and the bounty comes out of the bond of the party that failed.

## How it works

1. **Freeze.** The buyer locks USDC on Creditcoin against a job whose acceptance criteria are
   hashed before any work starts. The builder stakes a bond. Nothing in the contract can
   change that hash afterwards.
2. **Prove.** The outcome is an event on Ethereum Sepolia. Attestcoin proves that transaction
   on Creditcoin, receipt and logs included, inside one synchronous call.
3. **Settle.** A proved completion pays the builder. A proved failure refunds the buyer and
   pays whoever carried the proof a bounty out of the bond. Verification and payout happen in
   the same transaction.

## Two kinds of acceptance criterion, and one of them trusts nobody

| | Attested | Delivery |
|---|---|---|
| Source | our `WorkOracle`, with a named reporter set | any ordinary ERC-20 |
| Who must be trusted | whoever holds a reporter role | **nobody** |
| Good for | outcomes with no on-chain form | outcomes that are themselves on-chain |

A **delivery** job has no source-side trust assumption at all. Its criterion is an on-chain
fact produced by a token that has never heard of this project: the builder moved at least N
tokens to a named beneficiary, and the token's own `Transfer` log says so. Nobody can emit
that log without actually moving the tokens.

Transaction 03 below settles against canonical Sepolia WETH
([`0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`](https://sepolia.etherscan.io/address/0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14)).

## It runs. Five real transactions on CC3 Testnet.

**01 · Released.** A proved `WorkCompleted` paid the builder 1,200 tUSDC, the payout plus the bond returned.

- Settlement: [`0x02c42a8e6f780daef8ca59f985e2c2d008be2625df61d0b775a2a51b307ca23a`](https://creditcoin-testnet.blockscout.com/tx/0x02c42a8e6f780daef8ca59f985e2c2d008be2625df61d0b775a2a51b307ca23a)
- Source: [`0x6b331b41584e4a1c3acf222a34d36665595171269eddce481620c9e6a3b4e621`](https://sepolia.etherscan.io/tx/0x6b331b41584e4a1c3acf222a34d36665595171269eddce481620c9e6a3b4e621)

**02 · Refunded by a stranger.** A proved `WorkFailed`, carried to Creditcoin by
[`0xA0356B8011B63990978f2a7CCc389c3769d092Ea`](https://creditcoin-testnet.blockscout.com/address/0xA0356B8011B63990978f2a7CCc389c3769d092Ea), a wallet that is
**neither the buyer nor the builder**. Buyer refunded 1,100 tUSDC,
that wallet paid a **100 tUSDC bounty** out of the builder's
bond. This is the one nobody else proves.

- Settlement: [`0x90b4e9f403712c3d29c45d0315ef7ce1f4e0a47c8d2686dd9e38397aa4a471e8`](https://creditcoin-testnet.blockscout.com/tx/0x90b4e9f403712c3d29c45d0315ef7ce1f4e0a47c8d2686dd9e38397aa4a471e8)
- Source: [`0x54ffa5467a7a3f49470838f7409f399af244489a1c7d8c40726e8c68465a045b`](https://sepolia.etherscan.io/tx/0x54ffa5467a7a3f49470838f7409f399af244489a1c7d8c40726e8c68465a045b)

**03 · No oracle at all.** Settled by canonical WETH on Sepolia. The criterion was an on-chain
delivery of at least 0.001 WETH to the buyer, and WETH has no stake in the job.

- Settlement: [`0x21c775e8943d9691e5d50cc5b179e42fcdd6cf5218d5ffb3f8fcfb9026b522a4`](https://creditcoin-testnet.blockscout.com/tx/0x21c775e8943d9691e5d50cc5b179e42fcdd6cf5218d5ffb3f8fcfb9026b522a4)
- Source: [`0xd3d614577f9a0c1de462f2bb3469b6b17e22125ab47f936e48eaa348f40c2bf9`](https://sepolia.etherscan.io/tx/0xd3d614577f9a0c1de462f2bb3469b6b17e22125ab47f936e48eaa348f40c2bf9)

**04 · Replay refused, on purpose.** Proof 01 submitted a second time. Reverted with
`Query already processed`. The query id is derived by the precompile from the verified Merkle
path, not from anything the caller hands in.

- Settlement: [`0xf880148cf34fdc17fd3eb59ec7fbd26e09f066f89088367cdc4e43601908e96e`](https://creditcoin-testnet.blockscout.com/tx/0xf880148cf34fdc17fd3eb59ec7fbd26e09f066f89088367cdc4e43601908e96e)

**05 · Refused at the source, on purpose.** The builder tried to certify their own job on
Sepolia and was refused with `NotReporter`, before any proof could exist. An earlier version of
our oracle had no access control, which made every gate downstream decorative. We would rather
show you this than have you find it.

- Source: [`0x57d5187175be6066ed63e0e3c6d3580cd6437c7ab623b257392e571ce332436f`](https://sepolia.etherscan.io/tx/0x57d5187175be6066ed63e0e3c6d3580cd6437c7ab623b257392e571ce332436f)

## The gate that matters

```solidity
EvmV1Decoder.ReceiptFields memory receipt = ...;
if (receipt.receiptStatus != 1)
    revert ReceiptNotSuccessful(receipt.receiptStatus);
```

The precompile proves a transaction was **included in a block**. A reverted transaction is in
the block too. Without this line a builder sends a completion call, lets it revert, proves that
inclusion completely honestly, and is paid for work that never happened. Every proof in that
attack is genuine.

## Six gates on the settlement path

| Gate | Check | What it stops |
|---|---|---|
| G1 | `receiptStatus == 1` | a reverted call being paid as a success |
| G2 | emitter is registered | anyone deploying their own oracle and draining every escrow |
| G2b | proved chain id matches | the same bytecode redeployed on another attested chain |
| G3 | exact `topic0` and topic count | a different event settling a job |
| G4 | fields read from stored positions | indexed parameters read out of `data` as plausible garbage |
| G5 | query id unseen | the same proof settling twice |
| G6 | within the deadline | release and refund racing on transaction ordering |

The challenge path reuses G1 to G5 and deliberately **skips G6**. A failure stays provable
forever, or hiding one until the clock ran out would be a winning strategy.

## Attestcoin integration

- `JobEscrow` **inherits `ASCBase`** and settles through the protocol's own `execute()`.
  Replay protection and the query id are Attestcoin's, not ours.
- Proofs are verified by the **Block Prover precompile at
  [`0x0000000000000000000000000000000000000FD2`](https://creditcoin-testnet.blockscout.com/address/0x0000000000000000000000000000000000000FD2)**,
  called with a continuity proof and a Merkle proof from the Proof Builder service. We
  construct neither.
- `EvmV1Decoder` is **imported from the published package**, never copied in, so an upstream
  field change is a compile error instead of silent garbage.
- Sources are configuration: adding a chain or an emitter is one `registerSource` call.

Full write-up: [`docs/attestcoin-integration.md`](https://github.com/yukitran03/proveout/blob/main/docs/attestcoin-integration.md)

## Check it yourself, without a wallet

The precompile's `verify` is a **view** function, so the real verification path can be
exercised against real attestation state for free.

**[https://proveout.vercel.app/verify](https://proveout.vercel.app/verify)** — paste any Ethereum Sepolia transaction hash. It fetches a
real Merkle and continuity proof, calls the precompile on Creditcoin, and shows you the result,
the receipt status, and every log recovered from the proved bytes.

## Testing

```
118 tests passed, 0 failed
InvariantTest invariants (runs: 64, calls: 6144, reverts: 0)
```

Tests are named as claims rather than chores:

- `test_release_isRefused_whenReceiptStatusIsZero`
- `test_anyone_canForceRefund_withFailureProof`
- `test_delivery_needsNoReporterAndNoOracle`
- `test_builder_cannotCertifyTheirOwnWork`
- `test_releaseAndRefundWindows_neverOverlap`

## What this does NOT do

- **Attestcoin proves inclusion, not exclusion.** It can prove a transaction happened. It
  cannot prove none happened. ProveOut does not make hiding a failure impossible; it makes it
  **detectable and expensive**. That is the whole promise of the challenge mechanism.
- **An attested job trusts its oracle within its own scope.** A delivery job does not carry
  that assumption, because the token is not ours and cannot be asked to lie.
- **TestUSDC is not USDC.** A six-decimal demo token with an open mint and no value.
- **Testnet only, and unaudited.**
- **The bond ratio is a demo parameter**, not a modelled economic result.
- **Only transaction types 0 and 2 are accepted**, the two the shipped decoder fully decodes.
- **The relayer is not trusted, but it is not yet redundant.** Anyone can submit proofs; today
  only our worker does it automatically.

## Deployed

| Contract | Chain | Address |
|---|---|---|
| `JobEscrow` | Creditcoin CC3 Testnet | [`0xC69D0f7a0f4A59db88b74ef64439B643b8c9B65b`](https://creditcoin-testnet.blockscout.com/address/0xC69D0f7a0f4A59db88b74ef64439B643b8c9B65b) |
| `SourceRegistry` | Creditcoin CC3 Testnet | [`0x5f09023112d495b524486a5BcF0C8cD869acA657`](https://creditcoin-testnet.blockscout.com/address/0x5f09023112d495b524486a5BcF0C8cD869acA657) |
| `TestUSDC` | Creditcoin CC3 Testnet | [`0x5Cf6AC5c66d9448B5aCf4A85D29836369299e793`](https://creditcoin-testnet.blockscout.com/address/0x5Cf6AC5c66d9448B5aCf4A85D29836369299e793) |
| `WorkOracle` | Ethereum Sepolia | [`0xF38ac85b0cEC258dF08e8a45446f4f156EC591e9`](https://sepolia.etherscan.io/address/0xF38ac85b0cEC258dF08e8a45446f4f156EC591e9) |
| WETH9 (source) | Ethereum Sepolia | [`0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`](https://sepolia.etherscan.io/address/0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14) |

Creditcoin CC3 Testnet chain id `102031`. Source chain Ethereum Sepolia,
Attestcoin chain key `1`, EVM chain id `11155111`.

## Build log

Everything that was verified, everything that was assumed and turned out wrong, and the two
documentation errors found along the way: [`BUILD_LOG.md`](https://github.com/yukitran03/proveout/blob/main/BUILD_LOG.md)
