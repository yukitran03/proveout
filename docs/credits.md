# Credits

## Attestcoin / Gluwa

- **`@gluwa/asc-contracts`** - `ASCBase` and `EvmV1Decoder` are used *as shipped*, imported
  from the published package rather than copied into this repository. `JobEscrow` inherits
  `ASCBase`. Copying them in would have compiled fine and then decoded garbage the first
  time a field moved.
- **`@gluwa/usc-sdk`** (v0.18.0) - proof generation and the precompile client used by
  `worker/` and `spikes/`.
- **`gluwa/usc-testnet-bridge-examples`** (MIT) - read as the reference for correct usage.
  Two things are owed to it directly:
  - `contracts/foundry.toml` copies its verified toolchain settings (solc 0.8.30,
    `via_ir`, `evm_version = "shanghai"`, optimizer 200), because those are known to build
    and deploy on CC3.
  - The `receiptStatus == 1` check follows the pattern in their `ASCMinter.sol`.

  No contract code was copied from it.

## Interface

**[nymspace](https://github.com/hien-p/nymspace)** by Maverick Trinh, MIT.

The web interface follows nymspace's design language: the neutral shadcn token palette in
`oklch`, mono eyebrows in uppercase at wide tracking, small muted body text on a narrow
measure, generously spaced sections in a single column, underlined links, and soft-cornered
tinted callouts. Status colours are taken from nymspace's own data palette (the shamrock
and red ramps) rather than invented, so proved and refused read as part of one system.

What we did **not** take is the dependency tree. nymspace builds on Tailwind v4, shadcn and
the Astryx design system with a generated theme. This is a two page site; carrying a design
system CLI to render it would have been cost without benefit, so the same token values are
written as plain CSS in `web/app/globals.css`. No component code was copied.

## OpenZeppelin

`@openzeppelin/contracts` v5.6.1 (MIT) - `ERC20`, `SafeERC20`, `ReentrancyGuard`.

## Foundry

`forge-std` (MIT / Apache-2.0).

## Typefaces

Geist and Geist Mono, by Vercel (SIL Open Font License), served from Google Fonts.

## Not used

No code was taken from any project entered in this hackathon.
