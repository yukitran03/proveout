// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/**
 * @title ProvedTx
 * @notice Builds `encodedTransaction` blobs in the exact wire layout the shipped
 *         {EvmV1Decoder} expects, so unit tests can run offline.
 * @dev The layout is not invented here. It is read straight out of
 *      the file contracts/common/EvmV1Decoder.sol in the gluwa asc-contracts package:
 *
 *        encodedTx      = abi.encode(uint8 txType, bytes[] chunks)
 *        chunks[0]      = abi.encode(nonce, gasLimit, from, toIsNull, to, value, data)
 *        chunks[1]      = type-specific fields
 *        chunks[2]      = abi.encode(receiptStatus, gasUsed, LogEntryTuple[], logsBloom)
 *
 *      `spikes/spike1_prove.ts` decodes a REAL proved Sepolia transaction with the same
 *      layout and gets sane values back, which is what says these fixtures are shaped
 *      like production bytes rather than like our own assumptions.
 */
library ProvedTx {
    /// @dev A source-chain log to place in the fabricated receipt.
    struct Log {
        address emitter;
        bytes32[] topics;
        bytes data;
    }

    /// @notice Encode an EIP-1559 (type 2) transaction + receipt.
    function type2(uint64 chainId, uint8 receiptStatus, Log[] memory logs) internal pure returns (bytes memory) {
        bytes[] memory chunks = new bytes[](3);
        chunks[0] = _commonChunk();
        chunks[1] = abi.encode(
            chainId,
            uint128(1 gwei),
            uint128(30 gwei),
            new EvmV1Decoder.AccessListEntryBytes32[](0),
            uint8(0),
            bytes32(uint256(1)),
            bytes32(uint256(2))
        );
        chunks[2] = _receiptChunk(receiptStatus, logs);
        return abi.encode(uint8(2), chunks);
    }

    /// @notice Encode a legacy (type 0) transaction + receipt with an EIP-155 `v`.
    function type0(uint64 chainId, uint8 receiptStatus, Log[] memory logs) internal pure returns (bytes memory) {
        return _type0Raw(chainId * 2 + 35, receiptStatus, logs);
    }

    /// @notice Encode a legacy transaction with a pre-EIP-155 `v` (27), which carries no
    ///         chain id at all and must therefore be rejected.
    function type0PreEip155(uint8 receiptStatus, Log[] memory logs) internal pure returns (bytes memory) {
        return _type0Raw(27, receiptStatus, logs);
    }

    /// @notice Encode an unsupported transaction type (blob transaction, type 3).
    function type3(uint8 receiptStatus, Log[] memory logs) internal pure returns (bytes memory) {
        bytes[] memory chunks = new bytes[](4);
        chunks[0] = _commonChunk();
        chunks[1] = "";
        chunks[2] = "";
        chunks[3] = _receiptChunk(receiptStatus, logs);
        return abi.encode(uint8(3), chunks);
    }

    function _type0Raw(uint256 v, uint8 receiptStatus, Log[] memory logs) private pure returns (bytes memory) {
        bytes[] memory chunks = new bytes[](3);
        chunks[0] = _commonChunk();
        chunks[1] = abi.encode(uint128(20 gwei), v, bytes32(uint256(1)), bytes32(uint256(2)));
        chunks[2] = _receiptChunk(receiptStatus, logs);
        return abi.encode(uint8(0), chunks);
    }

    function _commonChunk() private pure returns (bytes memory) {
        return abi.encode(
            uint64(7), uint64(500_000), address(0xBEEF), false, address(0xCAFE), uint256(0), bytes("")
        );
    }

    function _receiptChunk(uint8 receiptStatus, Log[] memory logs) private pure returns (bytes memory) {
        EvmV1Decoder.LogEntryTuple[] memory tuples = new EvmV1Decoder.LogEntryTuple[](logs.length);
        for (uint256 i; i < logs.length; ++i) {
            tuples[i] =
                EvmV1Decoder.LogEntryTuple({address_: logs[i].emitter, topics: logs[i].topics, data: logs[i].data});
        }
        return abi.encode(receiptStatus, uint64(121_153), tuples, new bytes(256));
    }

    /// @dev Convenience: a one-log receipt.
    function one(Log memory log) internal pure returns (Log[] memory out) {
        out = new Log[](1);
        out[0] = log;
    }
}

/// @notice Stands in for the Block Prover precompile and always verifies.
contract MockBlockProver {
    function verifyAndEmit(
        uint64,
        uint64,
        bytes calldata,
        INativeQueryVerifier.MerkleProof calldata,
        INativeQueryVerifier.ContinuityProof calldata
    ) external pure returns (bool) {
        return true;
    }

    /// @dev Deterministic per Merkle root so distinct proofs get distinct query ids,
    ///      mirroring the real precompile deriving the index from the proof path.
    function calculateTxIndex(INativeQueryVerifier.MerkleProof calldata merkleProof)
        external
        pure
        returns (uint64)
    {
        return uint64(uint256(merkleProof.root) & 0xFFFF);
    }
}

/// @notice Stands in for the precompile refusing a proof.
contract RejectingBlockProver {
    function verifyAndEmit(
        uint64,
        uint64,
        bytes calldata,
        INativeQueryVerifier.MerkleProof calldata,
        INativeQueryVerifier.ContinuityProof calldata
    ) external pure returns (bool) {
        return false;
    }

    function calculateTxIndex(INativeQueryVerifier.MerkleProof calldata merkleProof)
        external
        pure
        returns (uint64)
    {
        return uint64(uint256(merkleProof.root) & 0xFFFF);
    }
}
