// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/**
 * @title WorkOracle
 * @notice Source-chain (Sepolia) contract whose events are the only thing ProveOut trusts.
 *
 * @dev Follows the Attestcoin "Source Chain Smart Contracts" pattern: keep logic on the
 *      source chain minimal and put every field the execution chain needs into a
 *      purpose-named event, so it lands in the transaction receipt logs and becomes provable.
 *
 *      Deliberately NOT using a generic event name. Attestcoin's design-pattern guidance is
 *      explicit that reusing a common signature (`Transfer`, `Done`) makes a query ambiguous:
 *      any contract emitting the same signature would satisfy a signature-only check.
 *
 *      This contract intentionally has NO access control. It cannot: a permissioned oracle
 *      would reintroduce the trusted operator ProveOut exists to remove. Authority comes from
 *      the escrow's registry deciding WHICH emitter address counts, not from who may call here.
 */
contract WorkOracle {
    /// @notice Agent finished a job; the escrow may release against this.
    /// @param jobId Job identifier, shared with the escrow on Creditcoin.
    /// @param criteriaHash Hash of the acceptance criteria, frozen at job creation.
    /// @param builder Address that performed the work and receives payment.
    /// @param outputHash Hash of the produced artifact, recorded for auditability.
    event WorkCompleted(
        bytes32 indexed jobId,
        bytes32 indexed criteriaHash,
        address indexed builder,
        bytes32 outputHash
    );

    /// @notice Job failed. Anyone may prove this to the escrow and force a refund.
    /// @param jobId Job identifier, shared with the escrow on Creditcoin.
    /// @param reason Short machine-readable failure reason.
    event WorkFailed(bytes32 indexed jobId, bytes32 indexed reason);

    /// @notice Signal completion of a job.
    function reportCompleted(bytes32 jobId, bytes32 criteriaHash, address builder, bytes32 outputHash) external {
        emit WorkCompleted(jobId, criteriaHash, builder, outputHash);
    }

    /// @notice Signal failure of a job.
    function reportFailed(bytes32 jobId, bytes32 reason) external {
        emit WorkFailed(jobId, reason);
    }
}
