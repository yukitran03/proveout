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

5 real transactions on CC3 Testnet, verifiable without a wallet.
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

4. Two kinds of source, both read through a configurable SourceRegistry that stores the
emitter, chain id, topic signatures and field positions. One is an attesting oracle whose
event names the job. The other is any ordinary ERC-20, where the acceptance criterion is the
Transfer itself: one of the five demo transactions settles against canonical Sepolia WETH,
which has no stake in the job and cannot be asked to lie.

5. Stated limit: inclusion is not exclusion. The challenge mechanism makes hiding a failure
detectable and expensive, not impossible.
```

## Project Detail / long description

Paste the whole of [`docs/PROJECT-DETAIL.md`](PROJECT-DETAIL.md). It is markdown, and the form
renders markdown. Every hash in it is a live link to an explorer.

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
https://proveout.vercel.app/demo.webm
```

A 3 minute screen recording with on-screen captions, no audio: the thesis, the live console,
all four transactions on their explorers, a real proof run on /verify, and the limitations.

**Also worth pasting into the description, because it is stronger than a recording:**

```
https://proveout.vercel.app/verify
```

> The live verifier: paste any Ethereum Sepolia transaction hash and it fetches a real
> proof, calls the real precompile on Creditcoin, and shows the result including receipt status
> and every recovered log. No wallet, nothing spent. If a recorded video is ready in time,
> replace this with its URL and keep the verifier link in the description.

## Live application

```
https://proveout.vercel.app
```

---

## The five transactions

Full hashes, for pasting into an explorer.

**1. Release — a proved `WorkCompleted` paid the builder 1,200 tUSDC**

```
Settlement (Creditcoin CC3): 0x02c42a8e6f780daef8ca59f985e2c2d008be2625df61d0b775a2a51b307ca23a
Source (Ethereum Sepolia):   0x6b331b41584e4a1c3acf222a34d36665595171269eddce481620c9e6a3b4e621
```

**2. Challenge — a proved `WorkFailed`, submitted by a wallet that is neither the buyer nor
the builder. Buyer refunded 1,100 tUSDC, submitter paid a 100 tUSDC bounty from the bond.**

```
Settlement (Creditcoin CC3): 0x90b4e9f403712c3d29c45d0315ef7ce1f4e0a47c8d2686dd9e38397aa4a471e8
Source (Ethereum Sepolia):   0x54ffa5467a7a3f49470838f7409f399af244489a1c7d8c40726e8c68465a045b
Submitted by:                0xA0356B8011B63990978f2a7CCc389c3769d092Ea
```

**3. Settled with no oracle at all — the acceptance criterion was an on-chain delivery, and
canonical WETH on Sepolia reported it. WETH has no stake in the job and cannot be asked to
lie: nobody can emit that Transfer without actually moving the tokens.**

```
Settlement (Creditcoin CC3): 0x21c775e8943d9691e5d50cc5b179e42fcdd6cf5218d5ffb3f8fcfb9026b522a4
Source (Ethereum Sepolia):   0xd3d614577f9a0c1de462f2bb3469b6b17e22125ab47f936e48eaa348f40c2bf9
Source token (WETH9):        0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
```

**4. Replay refused — proof 1 resubmitted, reverted with `Query already processed`**

```
Settlement (Creditcoin CC3): 0xf880148cf34fdc17fd3eb59ec7fbd26e09f066f89088367cdc4e43601908e96e
```

**5. Self-certification refused — the builder tried to declare their own job complete on the
source chain and was refused with `NotReporter`, before any proof could exist**

```
Source (Ethereum Sepolia):   0x57d5187175be6066ed63e0e3c6d3580cd6437c7ab623b257392e571ce332436f
```

## Contracts

```
JobEscrow       Creditcoin CC3 Testnet   0xC69D0f7a0f4A59db88b74ef64439B643b8c9B65b
SourceRegistry  Creditcoin CC3 Testnet   0x5f09023112d495b524486a5BcF0C8cD869acA657
TestUSDC        Creditcoin CC3 Testnet   0x5Cf6AC5c66d9448B5aCf4A85D29836369299e793
WorkOracle      Ethereum Sepolia         0xF38ac85b0cEC258dF08e8a45446f4f156EC591e9
WETH9 (source)  Ethereum Sepolia         0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
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
- [ ] All five transaction hashes paste cleanly into an explorer
- [ ] Submitted before 09:30 VN, leaving buffer ahead of the 10:59 deadline
- [ ] Vercel token rotated after the sprint, it travelled through a chat transcript
