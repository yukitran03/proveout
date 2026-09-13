# Technical Specification

## Contracts

| Contract | Chain | Role |
|---|---|---|
| `WorkOracle.sol` | Ethereum Sepolia | Emits `WorkCompleted` / `WorkFailed`. No access control, by design. |
| `SourceRegistry.sol` | Creditcoin CC3 | Which emitters are trusted, and the exact shape of their events. |
| `JobEscrow.sol` | Creditcoin CC3 | Holds funds; settles from proofs. Inherits `ASCBase`. |
| `TestUSDC.sol` | Creditcoin CC3 | Six-decimal demo settlement asset, open mint. |

## Events on the source chain

```solidity
event WorkCompleted(
    bytes32 indexed jobId,
    bytes32 indexed criteriaHash,
    address indexed builder,
    bytes32 outputHash
);
event WorkFailed(bytes32 indexed jobId, bytes32 indexed reason);
```

Deliberately specific names. Attestcoin's design guidance is explicit that a generic
signature makes a query ambiguous: any contract emitting `Transfer` would satisfy a
signature-only check.

`WorkOracle` has no owner and no allowlist. A permissioned oracle would reintroduce exactly
the trusted operator this project exists to remove. Authority lives in `SourceRegistry`
deciding *which emitter address counts*, not in who is allowed to call the oracle.

## State machine

```
None ──createJob──▶ Created ──postBond──▶ Created(bonded) ──fundJob──▶ Funded
                                                                        │
   execute(action=0, proof of WorkCompleted)  ─────────────────────────▶ Released
   execute(action=1, proof of WorkFailed), any caller ─────────────────▶ Refunded (+bounty)
   refund() after deadline ────────────────────────────────────────────▶ Refunded
```

Funds exist only in `Funded`. `Released` and `Refunded` are terminal; every settlement path
checks `status == Funded` first, so two paths can never both pay out.

`fundJob` requires the bond to be posted first, so the challenge path is funded from the
moment the buyer's money is at risk.

## Money

- `bond = amount * BOND_BPS / 10_000` (demo: 2000 bps = 20%)
- `bounty = bond * BOUNTY_BPS / 10_000` (demo: 5000 bps = 50% of the bond)

| Outcome | Builder | Buyer | Challenger |
|---|---|---|---|
| Release | `amount + bond` | — | — |
| Challenge | loses bond | `amount + (bond - bounty)` | `bounty` |
| Refund after deadline | loses bond | `amount + bond` | — |

`BOND_BPS` and `BOUNTY_BPS` are `immutable`, set at construction. Nothing can change them
for a live job.

## The vault invariant

```
token.balanceOf(escrow) + totalOut >= totalIn
```

An inequality, not an equality. Anyone can transfer tokens into any address; with `==` a
stranger sending one micro-unit would wedge every escrow in the contract permanently. The
invariant test's handler includes a `donate()` action for exactly this reason.

## Access control

`JobEscrow` has **no owner, no pause, no upgrade path, no sweep function**. The only code
that moves a user's tokens is `_settleRelease`, `_settleChallenge` and `refund`.
`SourceRegistry` has an owner, but that owner can only add or remove sources; removing one
cannot reach into the vault, which `test_escrow_hasNoAdminAbleToTouchUserFunds` asserts.

Registration is add-or-remove, never in-place edit. A silent redefinition of an existing
source would change how already-funded jobs settle.

## Toolchain

solc 0.8.30 · `via_ir = true` (required: `ASCBase` plus `EvmV1Decoder` hit stack-too-deep
without it) · `evm_version = "shanghai"` · optimizer 200 runs. These are copied from the
Attestcoin reference examples' own config, which is known to deploy on CC3.

`EvmV1Decoder` is an all-`internal` library, so it inlines at compile time and needs no
external library linking, despite also being deployed on CC3 at
`0x04B9ae8562D8Cc5bbbBbBB759080dDC30B56D18B`.

## Repository layout

```
contracts/   Foundry project: src, test, script
worker/      TypeScript relayer, deployer, and the three-scenario e2e run
spikes/      Standalone proofs that a protocol assumption is true
docs/        This directory
```

`spikes/` is kept in the repository on purpose. Each file is the smallest program that
proves one assumption before it was built on.
