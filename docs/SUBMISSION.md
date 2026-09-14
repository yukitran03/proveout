# Submission — copy and paste

Every figure below comes from [`FACTS.md`](FACTS.md). Nothing here is typed from memory.
No other project entered in this hackathon is named anywhere in this submission.

---

## Project Name

```
ProveOut
```

## Sector / Track

```
AI
```

## Description

*118 words.*

```
Money moves when the work is proved, and anyone can prove it failed.

ProveOut is a job escrow on Creditcoin CC3. A buyer locks USDC against a job whose
acceptance criteria are hashed and frozen before any work starts; the builder stakes a
bond. Settlement happens when an event on Ethereum Sepolia is verified on Creditcoin by the
Attestcoin Block Prover, inside a single synchronous transaction. No cross-chain oracle
operator, no arbiter, no approval step.

The difference is the challenge path. Where comparable designs let only the party who
benefits submit evidence, so a failure is never submitted at all, ProveOut lets any address
on earth prove a failure and pays them a bounty out of the bond of whoever failed.

4 real transactions on CC3 Testnet, verifiable without a wallet.
```

## Attestcoin Protocol Integration Summary

*196 words.*

```
1. JobEscrow inherits ASCBase and settles through the protocol's own execute(). Replay
protection and the query id are Attestcoin's, not ours: the id is keccak256(chainKey,
blockHeight, txIndex) where txIndex is derived by the precompile from the verified Merkle
path, rather than from a caller-supplied transaction hash. We tested that behaviour as if it
were our own code, because a dependency's guarantee is only a guarantee while something
checks it.

2. Proofs are verified by the Block Prover precompile at
0x0000000000000000000000000000000000000FD2, called with a continuity proof and a Merkle
proof obtained from the Proof Builder service. We construct neither; they are passed through
unmodified. EvmV1Decoder is imported from @gluwa/asc-contracts rather than copied in, so an
upstream field change is a compile error instead of silent garbage.

3. receiptStatus == 1 is mandatory. The precompile proves inclusion, not success, and a
reverted transaction is in the block too. Without this check a builder could prove a failed
call honestly and be paid for work that never happened.

4. Two event kinds, WorkCompleted and WorkFailed, read through a configurable
SourceRegistry that stores the emitter, chain id, topic signatures and field positions.

5. Stated limit: inclusion is not exclusion. The challenge mechanism makes hiding a failure
detectable and expensive, not impossible.
```

## GitHub URL

```
https://github.com/yukitran03/proveout
```

> **Switch the repository to public before submitting.** A private repo behind a submission
> link reads as though there is something to hide, and a judge cannot check the one thing the
> submission asks them to believe.

## Deck URL

```
https://proveout.vercel.app/ProveOut-deck.pdf
```

## Demo / Video URL

```
https://proveout.vercel.app/verify
```

> This is the live verifier: paste any Ethereum Sepolia transaction hash and it fetches a real
> proof, calls the real precompile on Creditcoin, and shows the result including receipt status
> and every recovered log. No wallet, nothing spent. If a recorded video is ready in time,
> replace this with its URL and keep the verifier link in the description.

## Live application

```
https://proveout.vercel.app
```

---

## The four transactions

Full hashes, for pasting into an explorer.

**1. Release — a proved `WorkCompleted` paid the builder 1,200 tUSDC**

```
Settlement (Creditcoin CC3): 0x507ab15719e304cd117580bfebccf705c3788a574743e2c889544e3fba72397e
Source (Ethereum Sepolia):   0xa81e6a2ee9b23067781feed1c696f368e2f3fb520f428a5001edf3bb15bff218
```

**2. Challenge — a proved `WorkFailed`, submitted by a wallet that is neither the buyer nor
the builder. Buyer refunded 1,100 tUSDC, submitter paid a 100 tUSDC bounty from the bond.**

```
Settlement (Creditcoin CC3): 0x8f9575743aef5fb49db6570e9f7b57dec4c361afd1d580f2c81e1778e8a915ac
Source (Ethereum Sepolia):   0xdec8b852679599b396cdd83f8ae4b45392284d4ea3d648d5953bc6a14e954b92
Submitted by:                0xA0356B8011B63990978f2a7CCc389c3769d092Ea
```

**3. Replay refused — proof 1 resubmitted, reverted with `Query already processed`**

```
Settlement (Creditcoin CC3): 0x06dab25c8d722886a110aa2be80b401819826552a65625ad1a7c93f60ca9c360
```

**4. Self-certification refused — the builder tried to declare their own job complete on the
source chain and was refused with `NotReporter`, before any proof could exist**

```
Source (Ethereum Sepolia):   0xa1ac8a598953c14cd21bd3f2669eccc8ca7d632fe5a83d77c5629b0dec42c775
```

## Contracts

```
JobEscrow       Creditcoin CC3 Testnet   0x9940f7659490E3e3dA3294397951eE84C3B28db4
SourceRegistry  Creditcoin CC3 Testnet   0x5f09023112d495b524486a5BcF0C8cD869acA657
TestUSDC        Creditcoin CC3 Testnet   0x5Cf6AC5c66d9448B5aCf4A85D29836369299e793
WorkOracle      Ethereum Sepolia         0x1e40b277AaB35D642c5F30A46276F46A6d3C11A9
Block Prover    Creditcoin CC3 Testnet   0x0000000000000000000000000000000000000FD2
```

Creditcoin CC3 Testnet chain id `102031`. Source chain Ethereum Sepolia, Attestcoin chain key
`1`, EVM chain id `11155111`.

## Team member fields

The form asks for these per member, and the last two are separate fields that are easy to
miss: full name, email, short bio, role, **country of residence**, **country of citizenship**.

## Before you press submit

- [ ] Repository switched to **public**
- [ ] Deck URL returns 200
- [ ] Video or demo URL returns 200
- [ ] All four transaction hashes paste cleanly into an explorer
- [ ] Submitted before 09:30 VN, leaving buffer ahead of the 10:59 deadline
- [ ] Vercel token rotated after the sprint, it travelled through a chat transcript
