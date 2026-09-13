// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/**
 * @title WorkOracle
 * @notice Source-chain (Sepolia) contract whose events are the only thing ProveOut trusts.
 *
 * @dev Follows the Attestcoin "Source Chain Smart Contracts" pattern: keep logic on the
 *      source chain minimal and put every field the execution chain needs into a
 *      purpose-named event, so it lands in the transaction receipt logs and becomes
 *      provable. Event names are deliberately specific rather than generic, because
 *      Attestcoin's design guidance is explicit that a shared signature makes a query
 *      ambiguous: any contract emitting `Transfer` would satisfy a signature-only check.
 *
 *      WHO MAY SPEAK HERE, AND WHY THIS CONTRACT HAS ACCESS CONTROL.
 *
 *      An earlier version of this contract let anyone emit either event, on the reasoning
 *      that a permissioned oracle would reintroduce the trusted operator ProveOut exists to
 *      remove. That reasoning was wrong, and the result was a complete bypass of the
 *      escrow: a builder could call {reportCompleted} naming their own job and their own
 *      address, prove that transaction honestly, and be paid for work that never happened.
 *      Every gate in the escrow passed, because every gate checks WHICH CONTRACT emitted a
 *      log and none of them can check who was allowed to call it. Symmetrically, anyone
 *      could emit {WorkFailed} against a funded job and burn an honest builder's bond.
 *
 *      The trust anchor was always the registry deciding which emitter counts. Leaving this
 *      contract open did not remove an operator; it let the beneficiary certify themselves.
 *
 *      So authority is explicit and narrow. A reporter is whoever the deploying platform
 *      authorises to observe jobs and state their outcome. That is the same shape of
 *      assumption every proof-carrying system makes about its source: Attestcoin proves
 *      what the source chain said, and who may speak on the source chain is an application
 *      decision. ProveOut removes the cross-chain oracle operator, the arbiter and the
 *      approval step. It does not, and cannot, remove the source of the fact.
 *
 *      What survives, and is the point of the project: once an outcome is on the source
 *      chain, settlement needs no further permission from anyone. **Any wallet on earth**
 *      can carry the proof to Creditcoin, and is paid to carry a failure. The party who
 *      stands to lose cannot suppress it.
 */
contract WorkOracle {
    error NotOwner();
    error NotReporter(address caller);
    error ZeroAddress();
    error AlreadyReporter(address reporter);
    error UnknownReporter(address reporter);

    /// @notice Address that may add and remove reporters.
    address public owner;

    /// @notice Addresses permitted to state a job outcome.
    mapping(address => bool) public isReporter;

    /// @notice Number of authorised reporters. Never allowed to reach zero by removal.
    uint256 public reporterCount;

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

    /// @notice Emitted when a reporter is authorised.
    event ReporterAdded(address indexed reporter);
    /// @notice Emitted when a reporter is revoked.
    event ReporterRemoved(address indexed reporter);
    /// @notice Emitted on ownership handover.
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyReporter() {
        if (!isReporter[msg.sender]) revert NotReporter(msg.sender);
        _;
    }

    /// @dev The deployer is the first reporter, so a fresh deployment is never in a state
    ///      where no outcome can be reported at all.
    constructor() {
        owner = msg.sender;
        isReporter[msg.sender] = true;
        reporterCount = 1;
        emit OwnerChanged(address(0), msg.sender);
        emit ReporterAdded(msg.sender);
    }

    /// @notice Hand the oracle to a new owner.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Authorise an address to state job outcomes.
    function addReporter(address reporter) external onlyOwner {
        if (reporter == address(0)) revert ZeroAddress();
        if (isReporter[reporter]) revert AlreadyReporter(reporter);
        isReporter[reporter] = true;
        unchecked {
            ++reporterCount;
        }
        emit ReporterAdded(reporter);
    }

    /**
     * @notice Revoke a reporter.
     * @dev The last reporter cannot be removed. A source contract with no one able to
     *      speak would strand every job that depends on it in the deadline-refund path,
     *      and the builder would lose a bond for a failure that was not theirs.
     */
    function removeReporter(address reporter) external onlyOwner {
        if (!isReporter[reporter]) revert UnknownReporter(reporter);
        if (reporterCount == 1) revert UnknownReporter(reporter);
        isReporter[reporter] = false;
        unchecked {
            --reporterCount;
        }
        emit ReporterRemoved(reporter);
    }

    /// @notice State that a job was completed. Reporters only.
    function reportCompleted(bytes32 jobId, bytes32 criteriaHash, address builder, bytes32 outputHash)
        external
        onlyReporter
    {
        emit WorkCompleted(jobId, criteriaHash, builder, outputHash);
    }

    /// @notice State that a job failed. Reporters only.
    /// @dev Gated for the same reason completion is. An open failure path is not a
    ///      censorship-resistance feature, it is a griefing primitive: any passer-by could
    ///      burn an honest builder's bond for the price of one transaction. Permissionless
    ///      participation belongs on the settlement side, where carrying this proof to
    ///      Creditcoin is open to everyone and pays a bounty.
    function reportFailed(bytes32 jobId, bytes32 reason) external onlyReporter {
        emit WorkFailed(jobId, reason);
    }
}
