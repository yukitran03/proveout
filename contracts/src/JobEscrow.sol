// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ASCBase} from "@gluwa/asc-contracts/contracts/readability/ASCBase.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";
import {SourceRegistry} from "./SourceRegistry.sol";

/**
 * @title JobEscrow
 * @notice Cross-chain job escrow settled only by proof. Money moves when a source-chain
 *         event is proved on Creditcoin, never because someone with a key said so.
 *
 * @dev Two ways out of escrow, and the second is the point of the project:
 *
 *      release   - prove `WorkCompleted` on the source chain, builder is paid.
 *      challenge - prove `WorkFailed` on the source chain. ANY address may do this, is paid
 *                  a bounty out of the builder's bond, and the buyer is refunded. This is
 *                  what makes the evidence adversarial: in a design where only the party
 *                  who benefits submits proof, a failure is simply never submitted.
 *
 *      Inherits {ASCBase} so the canonical Attestcoin entry point (`execute`) and its
 *      per-query replay guard are the ones the protocol ships, not ones we invented.
 *
 *      ON REPLAY PROTECTION - a deliberate, documented deviation. ProveOut's design note
 *      specified a nullifier of `keccak256(chainId, txHash, logIndex)`. The shipped
 *      {ASCBase} already dedupes on `keccak256(chainKey, blockHeight, txIndex)`, which is
 *      equivalent for uniqueness (a transaction index is unique within a block) and is
 *      derived by the protocol from the verified Merkle proof rather than from
 *      caller-supplied bytes. Adding a second, weaker nullifier beside it would be
 *      theatre. We use the protocol's.
 *
 *      Balance invariant is an INEQUALITY:
 *          token.balanceOf(this) + totalOut >= totalIn
 *      Anyone can push tokens into any address; if the contract demanded equality, a
 *      stranger sending one micro-unit would wedge every escrow in it forever.
 */
contract JobEscrow is ASCBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Which settlement path a proof is being submitted for.
    enum Action {
        Release, // 0
        ChallengeFailure // 1

    }

    /// @notice Lifecycle of a job. Funds only ever exist in `Funded`.
    enum Status {
        None,
        Created,
        Funded,
        Released,
        Refunded
    }

    /// @notice One escrowed job.
    struct Job {
        address buyer;
        address builder;
        address source; // expected source-chain emitter, frozen at creation
        uint128 amount; // payout to the builder, in token micro-units
        uint128 bond; // builder's stake, funds the challenge bounty
        uint64 deadline;
        bytes32 criteriaHash; // frozen before any work happens
        bool bondPosted;
        Status status;
    }

    error ZeroAddress();
    error ZeroAmount();
    error InvalidJobId();
    error InvalidCriteria();
    error InvalidDeadline();
    error InvalidBps();
    error JobAlreadyExists(bytes32 jobId);
    error WrongStatus(bytes32 jobId, Status actual, Status expected);
    error NotBuyer(bytes32 jobId);
    error NotBuilder(bytes32 jobId);
    error BondAlreadyPosted(bytes32 jobId);
    error BondNotPosted(bytes32 jobId);
    error DeadlinePassed(bytes32 jobId, uint64 deadline);
    error DeadlineNotReached(bytes32 jobId, uint64 deadline);
    error InvalidAction(uint8 action);
    error UnsupportedTxType(uint8 txType);
    error ReceiptNotSuccessful(uint8 receiptStatus);
    error NoMatchingLogs();
    error SourceChainMismatch(uint64 expected, uint64 proved);
    error SourceMismatch(bytes32 jobId, address expected, address proved);
    error CriteriaMismatch(bytes32 jobId, bytes32 expected, bytes32 proved);
    error BuilderMismatch(bytes32 jobId, address expected, address proved);

    /// @notice Settlement asset held in escrow.
    IERC20 public immutable TOKEN;
    /// @notice The set of source-chain emitters this escrow believes.
    SourceRegistry public immutable REGISTRY;
    /// @notice Builder's bond as basis points of the job amount.
    uint16 public immutable BOND_BPS;
    /// @notice Share of the bond paid to a successful challenger, in basis points.
    uint16 public immutable BOUNTY_BPS;

    /// @notice Cumulative tokens taken into escrow (amounts + bonds).
    uint256 public totalIn;
    /// @notice Cumulative tokens paid out of escrow.
    uint256 public totalOut;

    mapping(bytes32 => Job) private _jobs;

    event JobCreated(
        bytes32 indexed jobId,
        address indexed buyer,
        address indexed builder,
        uint128 amount,
        uint128 bond,
        uint64 deadline,
        bytes32 criteriaHash,
        address source
    );
    event BondPosted(bytes32 indexed jobId, address indexed builder, uint128 bond);
    event JobFunded(bytes32 indexed jobId, address indexed buyer, uint128 amount);
    event JobReleased(bytes32 indexed jobId, address indexed builder, uint128 amount, uint128 bond, bytes32 queryId);
    event JobChallenged(
        bytes32 indexed jobId, address indexed challenger, uint128 refunded, uint128 bounty, bytes32 queryId
    );
    event JobRefunded(bytes32 indexed jobId, address indexed buyer, uint128 amount, uint128 bond);

    /// @param token Settlement asset.
    /// @param registry Source-emitter registry.
    /// @param bondBps Builder bond as bps of the job amount (e.g. 2000 = 20%).
    /// @param bountyBps Challenger's share of the bond in bps (e.g. 5000 = 50%).
    constructor(IERC20 token, SourceRegistry registry, uint16 bondBps, uint16 bountyBps) {
        if (address(token) == address(0) || address(registry) == address(0)) revert ZeroAddress();
        if (bondBps == 0 || bondBps > 10_000 || bountyBps == 0 || bountyBps > 10_000) revert InvalidBps();
        TOKEN = token;
        REGISTRY = registry;
        BOND_BPS = bondBps;
        BOUNTY_BPS = bountyBps;
    }

    // ---------------------------------------------------------------- setup

    /// @notice Open a job with its acceptance criteria frozen before any work begins.
    /// @dev The criteria hash is written once, here, and every later proof is measured
    ///      against it. Nothing in this contract can change it afterwards.
    /// @param jobId Caller-chosen identifier, also emitted by the source-chain oracle.
    /// @param builder Address that will do the work and receive payment.
    /// @param amount Payout held in escrow, in token micro-units.
    /// @param deadline Unix time after which release is closed and refund opens.
    /// @param criteriaHash Hash of the acceptance criteria.
    /// @param source Source-chain emitter whose events settle this job.
    function createJob(
        bytes32 jobId,
        address builder,
        uint128 amount,
        uint64 deadline,
        bytes32 criteriaHash,
        address source
    ) external {
        if (jobId == bytes32(0)) revert InvalidJobId();
        if (builder == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (criteriaHash == bytes32(0)) revert InvalidCriteria();
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (_jobs[jobId].status != Status.None) revert JobAlreadyExists(jobId);
        // Fail now rather than at settlement time, when the money is already locked.
        REGISTRY.requireSource(source);

        uint128 bond = uint128((uint256(amount) * BOND_BPS) / 10_000);

        _jobs[jobId] = Job({
            buyer: msg.sender,
            builder: builder,
            source: source,
            amount: amount,
            bond: bond,
            deadline: deadline,
            criteriaHash: criteriaHash,
            bondPosted: false,
            status: Status.Created
        });

        emit JobCreated(jobId, msg.sender, builder, amount, bond, deadline, criteriaHash, source);
    }

    /// @notice Builder stakes the bond that a challenger can later claim against.
    function postBond(bytes32 jobId) external nonReentrant {
        Job storage job = _jobs[jobId];
        if (job.status != Status.Created) revert WrongStatus(jobId, job.status, Status.Created);
        if (msg.sender != job.builder) revert NotBuilder(jobId);
        if (job.bondPosted) revert BondAlreadyPosted(jobId);

        uint128 bond = job.bond;
        job.bondPosted = true;
        totalIn += bond;

        TOKEN.safeTransferFrom(msg.sender, address(this), bond);
        emit BondPosted(jobId, msg.sender, bond);
    }

    /// @notice Buyer locks the payout. Requires the bond to be up first, so the challenge
    ///         path is funded from the moment the money is at risk.
    function fundJob(bytes32 jobId) external nonReentrant {
        Job storage job = _jobs[jobId];
        if (job.status != Status.Created) revert WrongStatus(jobId, job.status, Status.Created);
        if (msg.sender != job.buyer) revert NotBuyer(jobId);
        if (!job.bondPosted) revert BondNotPosted(jobId);

        uint128 amount = job.amount;
        job.status = Status.Funded;
        totalIn += amount;

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit JobFunded(jobId, msg.sender, amount);
    }

    // ----------------------------------------------------------- settlement

    /**
     * @notice Settle jobs from a proved source-chain transaction.
     * @dev Reached only through {ASCBase-execute}, which has already
     *      called the Block Prover precompile and required it to return true, and
     *      required this query id to be unseen, then marked it seen.
     *      Everything below is the part the protocol cannot do for us: deciding whether
     *      this particular proved transaction says what this particular escrow needs.
     * @param action 0 = release, 1 = challenge failure.
     * @param queryId Protocol-derived id of the proved transaction.
     * @param encodedTransaction Proved transaction + receipt bytes.
     */
    function _processAndEmitEvent(uint8 action, bytes32 queryId, bytes memory encodedTransaction)
        internal
        override
        nonReentrant
    {
        if (action > uint8(Action.ChallengeFailure)) revert InvalidAction(action);

        (uint64 provedChainId, EvmV1Decoder.ReceiptFields memory receipt) = _decodeProved(encodedTransaction);

        // GATE 1. Inclusion is not success. The precompile proves the transaction was in a
        // block; a reverted transaction is in the block too. Without this check a builder
        // could send a WorkCompleted call that reverts and still be paid.
        if (receipt.receiptStatus != 1) revert ReceiptNotSuccessful(receipt.receiptStatus);

        uint256 settled;
        uint256 logCount = receipt.receiptLogs.length;
        for (uint256 i; i < logCount; ++i) {
            EvmV1Decoder.LogEntry memory logEntry = receipt.receiptLogs[i];

            // GATE 2. The emitter must be one we registered. This address comes from inside
            // the proved receipt, so the caller cannot choose it.
            SourceRegistry.Source memory src = REGISTRY.getSource(logEntry.address_);
            if (!src.registered) continue; // unrelated log in the same transaction

            // GATE 2b. The proved transaction's own chain id must match the chain we
            // registered that emitter on. Identical bytecode from an identical nonce lands
            // on an identical address on every EVM chain; without this, an attacker
            // redeploys the oracle on another supported chain and emits whatever they like.
            if (src.evmChainId != provedChainId) revert SourceChainMismatch(src.evmChainId, provedChainId);

            if (action == uint8(Action.Release)) {
                // GATE 3. Exact event signature and exact topic count.
                if (logEntry.topics.length != src.completedTopicCount) continue;
                if (logEntry.topics[0] != src.topic0Completed) continue;
                _settleRelease(queryId, logEntry, src);
            } else {
                if (logEntry.topics.length != src.failedTopicCount) continue;
                if (logEntry.topics[0] != src.topic0Failed) continue;
                _settleChallenge(queryId, logEntry, src);
            }
            unchecked {
                ++settled;
            }
        }

        if (settled == 0) revert NoMatchingLogs();
    }

    /// @dev Release path. Applies gates 4 and 6.
    function _settleRelease(bytes32 queryId, EvmV1Decoder.LogEntry memory logEntry, SourceRegistry.Source memory src)
        private
    {
        // GATE 4. Read each field from the position the registry recorded. Indexed
        // parameters live in topics[]; reading them out of `data` yields plausible garbage
        // rather than an error, which is why the layout is stored and not assumed.
        bytes32 jobId = logEntry.topics[src.completedJobIdTopic];
        bytes32 provedCriteria = logEntry.topics[src.completedCriteriaTopic];
        address provedBuilder = address(uint160(uint256(logEntry.topics[src.completedBuilderTopic])));

        Job storage job = _jobs[jobId];
        if (job.status != Status.Funded) revert WrongStatus(jobId, job.status, Status.Funded);
        if (job.source != logEntry.address_) revert SourceMismatch(jobId, job.source, logEntry.address_);
        if (job.criteriaHash != provedCriteria) revert CriteriaMismatch(jobId, job.criteriaHash, provedCriteria);
        if (job.builder != provedBuilder) revert BuilderMismatch(jobId, job.builder, provedBuilder);

        // GATE 6. Release and refund windows are disjoint: at any instant exactly one of
        // them is open, so there is no ordering race between a builder and a buyer.
        if (block.timestamp > job.deadline) revert DeadlinePassed(jobId, job.deadline);

        uint128 amount = job.amount;
        uint128 bond = job.bond;
        address builder = job.builder;

        job.status = Status.Released;
        totalOut += uint256(amount) + bond;

        TOKEN.safeTransfer(builder, uint256(amount) + bond);
        emit JobReleased(jobId, builder, amount, bond, queryId);
    }

    /// @dev Challenge path. Same gates as release except the deadline: a failure stays
    ///      provable forever, otherwise hiding one until the clock ran out would work.
    function _settleChallenge(bytes32 queryId, EvmV1Decoder.LogEntry memory logEntry, SourceRegistry.Source memory src)
        private
    {
        bytes32 jobId = logEntry.topics[src.failedJobIdTopic];

        Job storage job = _jobs[jobId];
        if (job.status != Status.Funded) revert WrongStatus(jobId, job.status, Status.Funded);
        if (job.source != logEntry.address_) revert SourceMismatch(jobId, job.source, logEntry.address_);

        uint128 amount = job.amount;
        uint128 bond = job.bond;
        uint128 bounty = uint128((uint256(bond) * BOUNTY_BPS) / 10_000);
        address buyer = job.buyer;

        job.status = Status.Refunded;
        totalOut += uint256(amount) + bond;

        TOKEN.safeTransfer(buyer, uint256(amount) + (bond - bounty));
        TOKEN.safeTransfer(msg.sender, bounty);
        emit JobChallenged(jobId, msg.sender, amount, bounty, queryId);
    }

    /// @notice Default exit. After the deadline with no release, the buyer takes back the
    ///         payout and the bond.
    function refund(bytes32 jobId) external nonReentrant {
        Job storage job = _jobs[jobId];
        if (job.status != Status.Funded) revert WrongStatus(jobId, job.status, Status.Funded);
        if (block.timestamp <= job.deadline) revert DeadlineNotReached(jobId, job.deadline);

        uint128 amount = job.amount;
        uint128 bond = job.bond;
        address buyer = job.buyer;

        job.status = Status.Refunded;
        totalOut += uint256(amount) + bond;

        TOKEN.safeTransfer(buyer, uint256(amount) + bond);
        emit JobRefunded(jobId, buyer, amount, bond);
    }

    // ---------------------------------------------------------------- views

    /// @notice Read a job.
    function getJob(bytes32 jobId) external view returns (Job memory) {
        return _jobs[jobId];
    }

    /// @notice The vault inequality. Holds at every point in the lifecycle.
    function vaultSolvent() external view returns (bool) {
        return TOKEN.balanceOf(address(this)) + totalOut >= totalIn;
    }

    // ------------------------------------------------------------- internal

    /// @dev Pull the chain id and receipt out of a proved transaction in one decode pass.
    ///      Only the transaction types {EvmV1Decoder} fully supports are accepted; an
    ///      unsupported type is rejected loudly rather than decoded on a guess.
    function _decodeProved(bytes memory encodedTransaction)
        private
        pure
        returns (uint64 provedChainId, EvmV1Decoder.ReceiptFields memory receipt)
    {
        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (txType == 2) {
            EvmV1Decoder.DecodedTransactionType2 memory d = EvmV1Decoder.decodeTransactionType2(encodedTransaction);
            return (d.type2.chainId, d.receipt);
        }
        if (txType == 0) {
            EvmV1Decoder.DecodedTransactionType0 memory d = EvmV1Decoder.decodeTransactionType0(encodedTransaction);
            // EIP-155: v = chainId * 2 + 35 or + 36. A pre-EIP-155 signature (v of 27/28)
            // carries no chain id at all and is therefore unusable here.
            if (d.type0.v < 35) revert UnsupportedTxType(txType);
            return (uint64((d.type0.v - 35) / 2), d.receipt);
        }
        revert UnsupportedTxType(txType);
    }
}
