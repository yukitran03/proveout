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

No component code, stylesheet or template was copied from anywhere. `web/` is written from
scratch, and its visual system is assembled from public design conventions:

- **shadcn/ui** (MIT) - the neutral token palette, used in its `oklch` form.
- **Tailwind CSS** (MIT) - the spacing, radius and type scales the layout is set on. The
  values are written as plain CSS here rather than pulled in as a dependency, since a two
  page site does not need a utility framework to render.
- **Astryx design system** (`@astryxdesign/core`) - the data colour ramps. Status colours
  are taken from its shamrock and red scales rather than invented, so proved and refused
  read as part of one system.
- **Geist and Geist Mono**, by Vercel (SIL Open Font License), served from Google Fonts.

## OpenZeppelin

`@openzeppelin/contracts` v5.6.1 (MIT) - `ERC20`, `SafeERC20`, `ReentrancyGuard`.

## Foundry

`forge-std` (MIT / Apache-2.0).

## Not used

No code was taken from any project entered in this hackathon, and no other entrant is
named, described or compared against anywhere in this repository.
