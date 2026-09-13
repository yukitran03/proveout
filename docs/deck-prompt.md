# Deck prompt — for Claude Design

Paste **section 2** into Claude Design as-is. Sections 1, 3 and 4 are reference material for
you, so you can answer follow-up questions Claude Design asks without inventing anything.

Every number in here was produced by a real run. If Claude Design proposes a figure that is
not in this file, delete it rather than letting it through. A judge who catches one invented
number stops believing the other twelve.

---

## 1. What this deck has to do

**Audience.** BUIDL CTC 2026 Fall judges, track AI. Assume at least one reader is a
Creditcoin or Gluwa engineer who has read the Attestcoin docs more carefully than we have,
and at least one is a CertiK reviewer who will go looking for the thing we glossed over.
Write for those two. Everyone else is served by the same deck.

**The single job of the deck.** Make a judge believe two things in order:

1. The usual way cross-chain settlement gets built has a hole in it that nobody names.
2. We closed it, it runs on their chain, and here are the transaction hashes.

**What loses.** A deck that opens with market size. A deck whose architecture slide is
prettier than its evidence slide. A deck with no limitations slide — with this audience,
admitting the boundary is what makes the rest credible.

**Length.** 12 slides. 16:9. Exported to PDF.

**Hard rules.**
- Never name, describe, or compare against another project entered in this hackathon.
  Where a contrast is needed, describe the *pattern* — "designs where the party who
  benefits is the only one who submits evidence." Judges who know the space will fill in
  the reference themselves, and that lands better than naming anyone.
- Never write a number that is not in this file.
- Do not claim the system is trustless, audited, or production-ready. It is none of those.

---

## 2. The prompt — paste this into Claude Design

> Design a 12-slide pitch deck, 16:9, for export to PDF. The project is **ProveOut**, a
> cross-chain job escrow submitted to the BUIDL CTC 2026 Fall hackathon, track AI.
>
> **Visual direction.** Quiet, technical, editorial — closer to a well-set engineering
> report than to a startup pitch. It should look like the people who made it care about
> being right. Warm off-white ground `#e9ebe6`, near-black ink `#131d1c`, secondary text
> `#495451`, hairline rules `#cdd2ca`, single accent `#8a5a1f` used sparingly for eyebrows
> and emphasis. Status colours only where semantically meaningful: success `#256b45`,
> caution `#8a6011`, failure `#8f3a33`. Sans-serif for prose, monospace for every address,
> hash, code fragment and number. Generous margins, strong left alignment, no gradients, no
> stock illustration, no drop shadows on text. Slide numbers small and bottom-right.
>
> Each slide gets one idea. If a slide needs a paragraph to explain it, the headline is
> wrong. Headlines should be claims, not labels: "Inclusion is not success", not
> "Technical details".
>
> ---
>
> **Slide 1 — Title**
> ProveOut
> Money moves when the work is proved — and anyone can prove it failed.
> Small footer: Creditcoin CC3 Testnet · Attestcoin readability · BUIDL CTC 2026 Fall, track AI
>
> **Slide 2 — The problem**
> Headline: An AI agent working across chains cannot be paid safely.
> Body: Pay first and the buyer loses the money if the work never happens. Pay after and the
> agent has no guarantee. Every existing answer inserts a third party to decide whether the
> work was done — an oracle operator, an arbiter, or the platform itself.
>
> **Slide 3 — The hole nobody names**
> Headline: Evidence that only the winner submits is not evidence.
> Body: The standard shape of a cross-chain settlement or reputation system is that the
> party who benefits watches for their own good news and submits it. A worker sees the
> repayment and posts it. A builder sees their own success and posts it.
> Pull-quote, large: **Nobody posts their own failure.**
> Closing line: Such a system does not need to censor bad news. Bad news simply never
> arrives, because the only party watching has no reason to send it.
>
> **Slide 4 — What ProveOut does**
> Three numbered columns.
> 01 Freeze — The buyer locks USDC on Creditcoin against a job whose acceptance criteria
> are hashed before any work starts. The builder stakes a bond. Nothing in the contract can
> change that hash afterwards.
> 02 Prove — The outcome is emitted as an event on Ethereum Sepolia. Attestcoin proves that
> transaction inside one synchronous Creditcoin call.
> 03 Settle — A proved completion pays the builder. A proved failure refunds the buyer and
> pays whoever submitted it a bounty out of the builder's bond.
>
> **Slide 5 — The difference, in one line**
> Centred, large, the only thing on the slide:
> **`challengeFailure` is callable by any address on earth, and it pays.**
> Below, smaller: The bounty comes out of the bond of the party that failed. Evidence stops
> being something the beneficiary curates.
>
> **Slide 6 — The gate that matters**
> Headline: Inclusion is not success.
> Code block, monospace:
> ```
> EvmV1Decoder.ReceiptFields memory receipt = ...;
> if (receipt.receiptStatus != 1) revert ReceiptNotSuccessful(receipt.receiptStatus);
> ```
> Body: The precompile proves a transaction was included in a block. A reverted transaction
> is in the block too. Without this line, a builder sends a completion call that reverts,
> proves its inclusion completely honestly, and is paid for work that never happened —
> every proof involved genuine.
> Footer: This is the pattern Gluwa's own reference ASC uses. We did not invent it; we
> refused to skip it.
>
> **Slide 7 — Architecture**
> A clean two-column diagram, no 3D, no icons beyond simple arrows.
> Left column "Ethereum Sepolia — source": `WorkOracle.sol`, emitting
> `WorkCompleted(jobId, criteriaHash, builder, outputHash)` and `WorkFailed(jobId, reason)`.
> Right column "Creditcoin CC3 — settlement": `SourceRegistry.sol` mapping emitter to chain
> key, EVM chain id, topic signatures and field positions; `JobEscrow.sol is ASCBase` with
> `execute(action=0) → release`, `execute(action=1) → challenge, any caller`, `refund()`
> after the deadline.
> One arrow left to right labelled: relayer waits for attestation, fetches the proof,
> submits it. Untrusted — anyone can do this.
> Caption under the diagram: Verification and payout happen in one Creditcoin transaction.
> No message queue, no second confirmation.
>
> **Slide 8 — Six gates**
> A dense but calm table. Columns: Gate / Check / What it stops.
> G1 · receiptStatus == 1 · a reverted call being paid as a success
> G2 · emitter is registered · anyone deploying their own oracle and draining every escrow
> G2b · proved chain id matches · the same bytecode redeployed on another attested chain
> G3 · exact topic0 and topic count · a different event settling a job
> G4 · fields read from registered positions · indexed parameters read out of `data` as plausible garbage
> G5 · query id unseen · the same proof settling twice
> G6 · within the deadline · release and refund racing on transaction ordering
> Footer line: The challenge path reuses G1–G5 and deliberately skips G6. A failure stays
> provable forever, or hiding one until the clock ran out would be a winning strategy.
>
> **Slide 9 — It runs. Here are the hashes.**
> This is the most important slide. Make it the most confident one.
> Three rows, monospace, each with what it proves and its transaction hash:
> 1 · A proved `WorkCompleted` paid the builder 1,200 tUSDC · `0x9a3c9b1d0a327cff81ba85f3456abfcf0ee810a1a8a69f8e2451665b9a2c1874` · status 1
> 2 · A proved `WorkFailed`, submitted by `0xA0356B8011B63990978f2a7CCc389c3769d092Ea` — neither the buyer nor the builder — refunded 1,100 tUSDC and paid that wallet a 100 tUSDC bounty · `0x6713f5e66d54554df8bf2603221300a890ae32bad8aa60de33015c92712a8966` · status 1
> 3 · Replaying proof #1 was refused on chain · `0xc4738c2976693c67365a8662923dd30e2c7dbc3d8048014ebd972bdd51a92836` · status 0, `Query already processed`
> Footer: Escrow afterwards — totalIn = totalOut = 2,400 tUSDC, vault invariant holds.
> Highlight row 2 visually. It is the only row that proves the thing nobody else proves.
>
> **Slide 10 — Integration depth**
> Headline: Verified, not assumed.
> Four short items:
> · Block Prover precompile `0x0000000000000000000000000000000000000FD2`, confirmed against
> the docs, against the shipped package constant, and by calling it.
> · `JobEscrow` inherits `ASCBase`, so the protocol's own entry point and replay guard are
> the ones in the path.
> · Replay protection uses the protocol's query id, derived by the precompile from the
> verified Merkle path — not a caller-supplied transaction hash.
> · 46 tests, 0 failing, including a 6,144-call invariant run on the vault balance rule.
> Small closing note: Two documentation errors found and reported during the build.
>
> **Slide 11 — What this does not do**
> Headline: The boundary, stated plainly.
> · Attestcoin proves inclusion, not exclusion. It can prove a transaction happened; it
> cannot prove none happened. ProveOut does not make hiding a failure impossible — it makes
> it detectable and expensive. That is the whole promise of the challenge mechanism.
> · TestUSDC is a demo token with an open mint and no value.
> · Testnet only, unaudited.
> · The bond ratio is a demo parameter, not a modelled economic result.
> Design this slide with the same care as slide 9. It is not an apology; it is the slide
> that makes the rest believable.
>
> **Slide 12 — Close**
> Repeat the one-line thesis: Money moves when the work is proved — and anyone can prove it
> failed.
> Then, in monospace:
> Live console · https://web-phuoap80r-yukitran03s-projects.vercel.app
> Repository · https://github.com/yukitran03/proveout
> Contracts · JobEscrow `0x6Ecf0f01DDE2b1872E6EA131c41De85e6a285BB6` on Creditcoin CC3 Testnet, chain id 102031
> Include a QR code to the live console, bottom-right, small and unobtrusive.

---

## 3. Facts Claude Design may ask for

Give it these verbatim if it asks. Do not improvise beyond them.

| | |
|---|---|
| Live console | https://web-phuoap80r-yukitran03s-projects.vercel.app |
| Repository | https://github.com/yukitran03/proveout |
| `JobEscrow` (CC3) | `0x6Ecf0f01DDE2b1872E6EA131c41De85e6a285BB6`, from block 5480951 |
| `SourceRegistry` (CC3) | `0x5995bdC12087884B5766433c59eb42b8EbB3C50D` |
| `TestUSDC` (CC3) | `0xD40002aA8a8faDd14723b90690051a368232654e` |
| `WorkOracle` (Sepolia) | `0xD40002aA8a8faDd14723b90690051a368232654e` |
| Block Prover precompile | `0x0000000000000000000000000000000000000FD2` |
| Creditcoin CC3 Testnet | chain id 102031 |
| Source chain | Ethereum Sepolia, Attestcoin chain key **1** (not its EVM chain id 11155111) |
| Explorer | https://creditcoin-testnet.blockscout.com |
| Tests | 46 passing, 0 failing; invariant run 64 × 96 = 6,144 calls, 0 reverts |
| Job economics in the demo | 1,000 tUSDC payout, 20% bond = 200, challenger bounty 50% of bond = 100 |
| Release proof | Sepolia block 11696158, txIndex 72, 7 merkle siblings, 3 continuity roots |
| Challenge proof | Sepolia block 11696203, txIndex 78, 7 merkle siblings, 8 continuity roots |
| Settlement gas | release 306,250 · challenge 307,888 · blocked replay 212,170 |
| Attestation latency | 7–9 minutes per proof, measured; matches the documented ~8–10 |

**One detail worth a sentence if there is room.** The first contract this deployer created
on Sepolia and the first it created on Creditcoin landed on the *same address*
`0xD40002aA…` — same deployer, same nonce, so CREATE put them in the same place on both
chains. That is exactly the cross-chain collision gate G2b exists to reject, demonstrated
by accident on our own first deployment. It is a good, true, memorable story, and it shows
the threat model came from thinking rather than from a checklist.

---

## 4. How to link the repository so a judge actually looks

A URL on a slide is not a link a judge follows. Make the path from deck to evidence short
and obvious, in this order of value:

1. **Slide 9 carries the hashes themselves**, not a link to them. A judge can paste one
   into Blockscout without leaving their seat. This is the single highest-value thing in
   the deck — the hashes are not decoration, they are the argument.
2. **QR code on the closing slide** pointing at the live console, not at the repo. The
   console shows the two settled jobs and the vault invariant in one screen; the repo is
   a wall of files. Send them to the thing that is immediately legible.
3. **Name `docs/attestcoin-integration.md` explicitly** on slide 10. Judges scoring
   "integration depth" want one file that answers exactly that, and telling them which file
   respects their time. Write the path in monospace so it reads as a real path.
4. **The DoraHacks "Attestcoin Protocol Integration Summary" field** should be the first
   two sections of `docs/attestcoin-integration.md`, pasted, not rewritten.

Before submitting, **switch the repository to public**. A private repo behind a deck link
is worse than no link: it reads as though there is something to hide, and the judge cannot
check the one thing the deck is asking them to believe.

---

## 5. Checks before you export

- [ ] No project entered in this hackathon is named or described anywhere.
- [ ] Every number on every slide appears in section 3 above.
- [ ] Slide 11 exists and is designed as carefully as slide 9.
- [ ] The three transaction hashes are complete, not truncated, and copy-pasteable.
- [ ] The repository is public and its README opens with the deployment block.
- [ ] Every link resolves. Click all four.
