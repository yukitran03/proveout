# Threat Model

Each gate exists because a specific attack works without it.

## The settlement gates

### G1 — `receiptStatus == 1`

**Attack.** The builder calls `WorkCompleted` in a way that reverts: out of gas, a failing
require, anything. The transaction is still mined and still in the block's transaction
trie. They generate a completely honest inclusion proof and submit it.

**Without the gate.** The escrow pays for work that never happened, and every proof
involved is genuine. This is the most dangerous failure mode in the design, because nothing
about it looks like an attack.

**Test.** `test_release_isRefused_whenReceiptStatusIsZero`

### G2 — emitter registered

**Attack.** Deploy your own contract on Sepolia. Emit a perfectly-formed `WorkCompleted`
naming someone else's funded job. Prove it honestly.

**Without the gate.** Every escrow in the contract is drainable by anyone, immediately.

**Test.** `test_release_isRefused_whenEmitterIsNotRegistered`

### G2b — proved chain id matches the registered chain

**Attack.** CC3 Testnet attests both Ethereum Sepolia (chain key 1) and Ethereum Mainnet
(chain key 3). Deploy the same oracle bytecode from the same nonce on the other chain; it
lands at the same address. Emit whatever you like there and prove it.

**Without the gate.** The registry's emitter check is satisfied by a contract on a chain
the operator never intended to trust.

**Test.** `test_release_isRefused_whenProvedChainIdIsNotTheRegisteredChain`

### G3 — exact `topic0` and topic count

**Attack.** Get the registered oracle to emit some other event, or an event of the same
name with different arity, and have it read as a completion.

**Test.** `test_release_isRefused_whenTopic0IsNotWorkCompleted`,
`test_release_isRefused_whenTopicCountIsWrong`

### G4 — fields read from registered positions

**Attack.** Not an attack so much as a latent bug with the same consequences. Indexed
parameters live in `topics[]`, non-indexed ones in `data`. Reading from the wrong place
returns a well-formed wrong value rather than reverting, so a mistake here settles the
wrong job for the wrong amount and looks fine while doing it.

**Test.** `test_release_isRefused_whenCriteriaHashDiffersFromTheFrozenOne`,
`test_release_isRefused_whenBuilderInTopicIsNotTheJobBuilder`

### G5 — query id unseen

**Attack.** Submit the same winning proof repeatedly, or reuse a proof from a settled job
against a new one.

**Test.** `Replay.t.sol`, five tests.

### G6 — within the deadline

**Attack.** Not theft; a race. If release and refund were ever simultaneously legal, the
builder and the buyer would be competing on transaction ordering for the same money.

**Test.** `test_releaseAndRefundWindows_neverOverlap`

## Attacks on the challenge path

### Griefing an honest builder

Anyone can emit `WorkFailed` from their own contract and try to force a refund, destroying
an honest builder's bond.

**Stopped by** G2 and G2b: a failure proof only counts from the registered oracle on the
registered chain.

**Test.** `test_challenge_isRefused_whenEmitterIsNotRegistered`

### Double settlement

A builder's release and a challenger's failure proof land in the same block.

**Stopped by** the `status == Funded` check at the head of every settlement path. Whichever
is mined first wins outright; the second reverts rather than paying twice.

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
  no transaction happened. If a failure is never emitted on the source chain, there is
  nothing to prove, and the escrow falls back to the deadline refund. ProveOut makes hiding
  a failure *detectable and expensive*, not impossible. Every other item in this document
  is smaller than this limitation.
- **Bounty economics are unmodelled.** Whether 50% of a 20% bond is enough to make anyone
  watch for failures is an economic question this project has not answered.
- **Oracle honesty is assumed within its own scope.** Whoever controls what `WorkOracle`
  gets called with controls what is provable. ProveOut moves trust from a cross-chain
  message relayer to a named source-chain contract; it does not eliminate trust.
- **Registry owner is a trusted role.** They cannot touch escrowed funds, but they choose
  which emitters count. A production deployment would put that key behind a timelock.
- **No audit.** Testnet only, unaudited.
