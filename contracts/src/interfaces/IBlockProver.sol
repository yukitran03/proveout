// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/**
 * @title IBlockProver
 * @notice ProveOut's single entry point to the Attestcoin Block Prover precompile.
 *
 * @dev VERIFIED, not remembered. The precompile lives at
 *      `0x0000000000000000000000000000000000000FD2` (4050) on Creditcoin CC3.
 *      Confirmed three ways before a line of this project was written:
 *        1. docs.attestcoin.org -> Attestcoin Smart Contracts (address + `verify`/`verifyAndEmit`)
 *        2. docs.attestcoin.org -> Environments/Testnet links the live Blockscout page for it
 *        3. `spikes/spike1_prove.ts` called it against a real Sepolia transaction and got `true`
 *
 *      We deliberately RE-EXPORT the canonical declaration shipped in
 *      the gluwa asc-contracts package instead of hand-copying the struct and parameter
 *      order into this repo. A hand-copy is a silent liability: if Gluwa
 *      reorders a field, a copy keeps compiling and starts decoding garbage.
 *      Importing the published declaration makes any such change a compile error.
 */
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/// @dev Re-exported so the rest of the repo imports the prover through one file.
// solhint-disable-next-line no-empty-blocks
interface IBlockProver is INativeQueryVerifier {}
