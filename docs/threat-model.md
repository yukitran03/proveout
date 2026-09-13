# Threat Model

Each gate exists because a specific attack works without it.

## Where authority actually sits

Worth stating before the gate list, because a reader who gets this wrong will mis-read
everything below it.

Attestcoin proves **what the source chain said**. It cannot tell you whether the contract
that said it is one you should believe, or whether the account that called that contract was
entitled to. Those are application decisions, and ProveOut makes them in two places:

- `SourceRegistry` decides **which emitter counts**, and on which chain.
- `WorkOracle` decides **who may speak through that emitter**.

ProveOut removes the cross-chain oracle operator, the arbiter and the approval step. It does
not remove the source of the fact, and no proof system can. What it does guarantee is that
once an outcome exists on the source chain, the party it goes against cannot stop it reaching
the escrow: carrying the proof is open to anyone and carrying a failure is paid.

### The bug this section is written around

An earlier version of `WorkOracle` had **no access control at all**, on the reasoning that a
permissioned oracle would reintroduce the trusted operator the project exists to remove.

That reasoning was wrong, and the result was a total bypass:

- A builder could call `reportCompleted` naming their own job, their own criteria hash and
  their own address, prove that transaction completely honestly, and be paid for work that
  never happened. **Every gate below passed.** They all check *which contract* emitted a log;
  none of them can check who was allowed to call it.
- Symmetrically, any passer-by could call `reportFailed` against a funded job and burn an
  honest builder's bond for the price of one transaction, collecting the challenge bounty for
  doing it.

The trust anchor was always the registry deciding which emitter counts. Leaving the oracle
open did not remove an operator; it let the beneficiary certify themselves. `WorkOracle` now
carries an owner-managed reporter set, and transaction 04 of the demo is a builder being
refused at the source chain, on chain, for the record.

## The settlement gates

### G1 - `receiptStatus == 1`

**Attack.** The builder calls `WorkCompleted` in a way that reverts: out of gas, a failing
require, anything. The transaction is still mined and still in the block's transaction trie.
They generate a completely honest inclusion proof and submit it.

**Without the gate.** The escrow pays for work that never happened, and every proof involved
is genuine. This is the most dangerous failure mode in the design, because nothing about it
looks like an attack.

**Test.** `test_release_isRefused_whenReceiptStatusIsZero`

### G2 - emitter registered

**Attack.** Deploy your own contract on Sepolia. Emit a perfectly-formed `WorkCompleted`
naming someone else's funded job. Prove it honestly.

**Without the gate.** Every escrow in the contract is drainable by anyone, immediately.

**Test.** `test_release_isRefused_whenEmitterIsNotRegistered`

### G2b - proved chain id matches the registered chain

**Attack.** CC3 Testnet attests both Ethereum Sepolia (chain key 1) and Ethereum Mainnet
(chain key 3). Deploy the same oracle bytecode from the same nonce on the other chain; it
lands at the same address. Emit whatever you like there and prove it.

**Without the gate.** The registry's emitter check is satisfied by a contract on a chain the
operator never intended to trust.

This is not hypothetical here. The first contract this project deployed on Sepolia and the
first it deployed on Creditcoin landed on the *same address*, from the same deployer at the
same nonce, on the first run.

**Test.** `test_release_isRefused_whenProvedChainIdIsNotTheRegisteredChain`

### G3 - exact `topic0` and topic count

**Attack.** Get the registered oracle to emit some other event, or an event of the same name
with different arity, and have it read as a completion.

**Test.** `test_release_isRefused_whenTopic0IsNotWorkCompleted`,
`test_release_isRefused_whenTopicCountIsWrong`

### G4 - fields read from registered positions

**Attack.** Not an attack so much as a latent bug with the same consequences. Indexed
parameters live in `topics[]`, non-indexed ones in `data`. Reading from the wrong place
returns a well-formed wrong value rather than reverting, so a mistake here settles the wrong
job for the wrong amount and looks fine while doing it.

**Test.** `test_release_isRefused_whenCriteriaHashDiffersFromTheFrozenOne`,
`test_release_isRefused_whenBuilderInTopicIsNotTheJobBuilder`

### G5 - query id unseen

**Attack.** Submit the same winning proof repeatedly, or reuse a proof from a settled job
against a new one.

**Test.** `Replay.t.sol`, five tests.

### G6 - within the deadline

**Attack.** Not theft; a race. If release and refund were ever simultaneously legal, the
builder and the buyer would be competing on transaction ordering for the same money.

**Test.** `test_releaseAndRefundWindows_neverOverlap`

## Attacks on the source chain

### Self-certification

**Attack.** The party who gets paid declares their own success.

**Stopped by** the reporter set on `WorkOracle`. A builder holds no reporter role, so the
call reverts on Sepolia before a provable transaction exists.

**Test.** `test_builder_cannotCertifyTheirOwnWork`, and demo transaction 04.

### Griefing an honest builder

**Attack.** Emit `WorkFailed` against a funded job, prove it, and collect the bounty out of a
bond belonging to someone who did nothing wrong.

**Stopped by** the same reporter set. An open failure path is not censorship resistance, it is
a griefing primitive. Permissionless participation belongs on the settlement side, where
carrying a proof to Creditcoin is open to everyone and pays.

**Test.** `test_stranger_cannotBurnAnHonestBuildersBond`

### Silencing the oracle

**Attack.** Revoke every reporter so no outcome can ever be stated, stranding funded jobs.

**Stopped by** refusing to remove the last reporter. Jobs still fall back to the deadline
refund, but a builder would lose a bond for a failure that was not theirs.

**Test.** `test_lastReporter_cannotBeRemoved`

## Attacks on the challenge path

### Double settlement

A builder's release and a challenger's failure proof land in the same block.

**Stopped by** the `status == Funded` check at the head of every settlement path. Whichever is
mined first wins outright; the second reverts rather than paying twice.

**Test.** `test_releaseAndChallenge_cannotBothSettleTheSameJob`

### Challenging after the deadline

Deliberately allowed. If the challenge window closed with the release window, sitting on a
known failure until the clock ran out would be a winning strategy.

**Test.** `test_challenge_stillWorks_afterTheDeadline`

### Bounty theft by the submitter

The bounty goes to `msg.sender`, so a relayer could front-run a challenger's proof and take
it. This is real and unmitigated. It is also self-limiting: whoever submits first still
performs the service the bounty pays for, and the buyer is refunded either way. The failure
mode is a redistribution between challengers, not a loss to the escrow.

## What is NOT defended

- **Inclusion is not exclusion.** Attestcoin proves a transaction happened. It cannot prove
  no transaction happened. If a failure is never emitted on the source chain, there is nothing
  to prove, and the escrow falls back to the deadline refund. ProveOut makes hiding a failure
  *detectable and expensive*, not impossible. Every other item in this document is smaller
  than this limitation.
- **A dishonest reporter.** A reporter can state an outcome that is not true, or refuse to
  state one at all. Refusal degrades to the deadline refund. A false completion is the
  residual trust in this design, and it is the same shape of assumption every proof-carrying
  system makes about its source. A production deployment would put the reporter set behind a
  timelock, and would be better served by a source event emitted by a protocol with no stake
  in the outcome.
- **Registry and oracle owners are trusted roles.** Neither can touch escrowed funds, but
  between them they choose which emitters count and who may speak. Both belong behind a
  timelock in production.
- **Bounty economics are unmodelled.** Whether 50 percent of a 20 percent bond is enough to
  make anyone watch for failures is an economic question this project has not answered.
- **No audit.** Testnet only, unaudited.
