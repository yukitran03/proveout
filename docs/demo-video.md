# Demo video — shot list and script

Target: **2 minutes 45 seconds.** Judges watch a lot of these. A tight 2:45 that proves one
thing beats a 5:00 that tours a codebase.

The script below is written to be *spoken*, not read. Short sentences, contractions, one
idea per breath. Read it out loud once before recording; anything you stumble over, change
to whatever you said instead — your version will be better than the written one.

---

## The production problem, and how to work around it

Attestation takes **7 to 9 minutes** per proof. You cannot record a settlement in real time
without nine minutes of dead air, and you must not fake it by cutting and pretending it was
instant — that is the one thing this project is about not doing.

So: **state the wait out loud and cut honestly.** "This takes about eight minutes, because
Attestcoin deliberately lags the source chain so a reorg can't be attested into permanence.
I'll skip ahead." A judge who knows the protocol will respect that you know why the delay
exists. Pretending it is instant tells them you don't.

There is one thing that *is* fast and live: `spikes/spike1_prove.ts` calls the real
precompile and returns in seconds. Use that for your live moment.

### Before you hit record

```bash
cd ~/dev/proveout

# 1. Confirm the deployment is still readable
npm run finalize

# 2. Start a fresh job and emit its completion on Sepolia NOW, so the
#    attestation is ready by the time you get to scene 4.
#    (Or reuse the existing settled jobs and narrate over them — simpler,
#    and the console already shows both outcomes.)

# 3. Have the test suite ready to run on camera — it takes about a second
npm run test
```

Open these tabs, in this order, and leave them open:

1. The live console — https://proveout.vercel.app/console
2. Blockscout, the **challenge** transaction:
   `https://creditcoin-testnet.blockscout.com/tx/0x6713f5e66d54554df8bf2603221300a890ae32bad8aa60de33015c92712a8966`
3. Blockscout, the **blocked replay**:
   `https://creditcoin-testnet.blockscout.com/tx/0xc4738c2976693c67365a8662923dd30e2c7dbc3d8048014ebd972bdd51a92836`
4. `contracts/src/JobEscrow.sol` in your editor, scrolled to `_processAndEmitEvent`
5. A terminal, in the repo, font size **16pt or larger**

Terminal and editor both in a light theme if you can — it reads better after video
compression than dark grey text on black, and it matches the deck.

Record at 1080p. Hide your bookmarks bar, your notifications, and anything with a personal
email address in it. Do a ten-second test recording and actually watch it back.

---

## Shot list

| # | Time | On screen | Purpose |
|---|---|---|---|
| 1 | 0:00–0:18 | You, or a plain title card | State the problem |
| 2 | 0:18–0:42 | Title card or slide 3 of the deck | The insight |
| 3 | 0:42–1:05 | Live console | Show it exists and settles |
| 4 | 1:05–1:45 | Blockscout, challenge tx | **The money shot** |
| 5 | 1:45–2:12 | Editor, `JobEscrow.sol` + terminal running tests | The gate that matters |
| 6 | 2:12–2:30 | Blockscout, reverted replay | Replay protection |
| 7 | 2:30–2:45 | Console or title card | Honest limit, close |

---

## Script

Stage directions are in brackets. Everything else is spoken.

### Scene 1 — 0:00 to 0:18

> If you hire an AI agent across two chains, there's no safe way to pay it.
>
> Pay up front, and you lose the money if the work never happens. Pay after, and the agent
> has no guarantee it'll ever get paid.
>
> [beat]
>
> Every fix for this puts someone in the middle. An oracle operator. An arbiter. The
> platform. Someone who decides whether the job was done.

### Scene 2 — 0:18 to 0:42

> So people build cross-chain systems where you prove what happened. And that mostly works.
> But there's a hole in how they're usually built, and I don't think it gets said out loud
> enough.
>
> The party who benefits is the one who submits the evidence. The worker sees the repayment
> and posts it. The builder finishes the job and posts the receipt.
>
> [slow down here — this is the line the whole thing rests on]
>
> Nobody posts their own failure.
>
> That system doesn't need to censor bad news. Bad news just never shows up. The only
> person watching has no reason to send it.

### Scene 3 — 0:42 to 1:05

> [switch to the live console]
>
> This is ProveOut, running on Creditcoin CC3 testnet.
>
> A buyer locks USDC against a job. The acceptance criteria get hashed and frozen before
> anyone starts work. The builder puts up a bond.
>
> [point at the two rows]
>
> Two jobs here. One released — the builder got paid. One refunded. And the vault invariant
> holds: everything that went in is accounted for.
>
> The interesting one is the refund.

### Scene 4 — 1:05 to 1:45 · the money shot

> [switch to Blockscout, the challenge transaction. Zoom in on the `from` address.]
>
> This transaction refunded the buyer. Look at who sent it.
>
> That address isn't the buyer. It isn't the builder either. It's a third wallet, with no
> stake in this job at all.
>
> [beat]
>
> It proved that the job emitted a failure event on Sepolia. The escrow verified that proof
> against Attestcoin's block prover, refunded the buyer eleven hundred, and paid this
> wallet a hundred-token bounty — out of the builder's bond.
>
> So the person who failed paid for being caught. And anyone on earth can be the one who
> catches them. That's `challengeFailure`, and it's callable by any address.
>
> That's the whole idea. Evidence stops being something the winner gets to curate.

### Scene 5 — 1:45 to 2:12

> [switch to the editor, `JobEscrow.sol`, on the receipt check]
>
> One line I want to show you, because it's the easiest thing to get wrong here.
>
> The precompile proves a transaction was *included in a block*. It does not prove the
> transaction *succeeded*. And a reverted transaction is still in the block.
>
> So without this check — [highlight `if (receipt.receiptStatus != 1) revert`] — a builder
> could call "work completed", let it revert, prove that inclusion completely honestly, and
> get paid for work that never happened. Every proof in that attack is real.
>
> [switch to terminal, run `npm run test`, let it finish on camera]
>
> Forty-six tests. The one named `test_release_isRefused_whenReceiptStatusIsZero` is that
> attack, and it's the most important test in the repo.

### Scene 6 — 2:12 to 2:30

> [switch to Blockscout, the reverted replay transaction]
>
> Last one. This transaction failed, and it's supposed to.
>
> I took the proof that paid the builder in the first job and submitted it a second time.
> Reverted. "Query already processed."
>
> That's the protocol's own replay guard — the query id comes from the verified Merkle
> path, not from anything the caller hands in.

### Scene 7 — 2:30 to 2:45

> [back to the console, or a plain card]
>
> One honest limitation, because it matters.
>
> Attestcoin can prove a transaction happened. It can't prove that *no* transaction
> happened. So this doesn't make hiding a failure impossible. It makes hiding one
> detectable, and expensive.
>
> [beat]
>
> That's all the challenge mechanism promises. But it's a lot more than a system where
> nobody was ever going to look.
>
> Money moves when the work is proved. And anyone can prove it failed. Thanks for watching.

---

## Making it sound like a person

The difference between this and AI narration is mostly rhythm and restraint.

**Do:**
- Vary your sentence length hard. A long explanatory sentence, then three words. That
  contrast is what reads as human.
- Leave real pauses where the brackets say `[beat]`. Two full seconds feels enormous while
  you're recording and correct on playback. Do not fill them.
- Say "I" when you did something. "I took the proof that paid the builder and submitted it
  again." Not "the proof was resubmitted."
- Keep one small imperfection. A slight stumble you recover from, or an aside like "this is
  the bit I got wrong the first time." Perfectly smooth reads as recorded copy.
- Talk to one person. You're showing this to a colleague, not addressing a room.

**Don't:**
- No "solution", "leverage", "seamless", "robust", "cutting-edge", "revolutionize",
  "empower". No "in today's rapidly evolving landscape."
- Don't list features. Every claim in this script is attached to something visible on
  screen. Keep that rule.
- Don't oversell the limitation slide by rushing it. Slow down there instead. Judges have
  watched twenty confident demos that fell apart under one question; being the one that
  names its own boundary is a differentiator.
- Don't read the numbers off the screen. The viewer can see them. Say what they *mean*.

**On accent and delivery.** Don't flatten your accent or speed up to sound more fluent —
it makes you harder to follow, not more credible. Speak a little slower than feels natural
and finish every word. If English isn't your first language, unhurried and clear beats fast
and smooth every single time. Judges are listening for whether you understand your own
system, and that comes through regardless of accent.

**If you fluff a line**, don't restart the take. Pause, breathe, say the line again cleanly,
and cut it in post. Restarting from the top five times makes take six sound exhausted.

---

## Before you upload

- [ ] 2:45 or under.
- [ ] Audio is clean — no fan, no keyboard clatter under the voice. Record audio separately
      on your phone if the laptop mic is rough; it's worth the sync work.
- [ ] The `from` address on the challenge transaction is legible at 1080p. Zoom in if not.
      If a judge cannot read that address, scene 4 proves nothing.
- [ ] No personal email, no private key, no wallet with real funds visible anywhere.
- [ ] You said the attestation wait is real and why. You did not imply it was instant.
- [ ] No other hackathon project is named.
- [ ] Watch the whole thing once at 1x without touching anything. If you get bored, the
      judge will too — cut that part.
