// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/**
 * @title SourceRegistry
 * @notice The list of source-chain emitters ProveOut is willing to believe, and the exact
 *         shape of their events.
 *
 * @dev This is the contract that makes a proof mean something. The Attestcoin precompile
 *      proves that a transaction was included in a source-chain block. It does not and
 *      cannot know whether the contract that emitted a log inside it is one you trust.
 *      Without this registry, anyone could deploy their own contract on Sepolia, emit a
 *      perfectly-formed completion event, prove it honestly, and drain every escrow.
 *
 *      Keyed by emitter address rather than by chain key, because the emitter address is
 *      the one field that comes from INSIDE the proved receipt and so cannot be chosen by
 *      the caller. `evmChainId` is checked against the proved transaction's own chain id,
 *      which closes the cross-chain address-collision hole: the same bytecode deployed from
 *      the same nonce lands on the same address on every EVM chain.
 *
 *      Field positions are stored, not assumed. Indexed event parameters live in `topics[]`
 *      and non-indexed ones in `data`; reading a field from the wrong place does not fail
 *      loudly, it returns a plausible-looking wrong value.
 *
 *      TWO KINDS OF SOURCE, AND WHY THE SECOND ONE MATTERS.
 *
 *      `Attested` is a contract that exists to report job outcomes: ProveOut's own
 *      `WorkOracle`. It names the job directly, and the trust you place in it is trust in
 *      whoever may speak through it.
 *
 *      `Delivery` is any ordinary ERC-20, unmodified, deployed by someone with no interest
 *      in the job at all. A job settled this way does not ask anyone whether the work was
 *      done. Its acceptance criterion IS an on-chain fact: the builder moved at least N
 *      tokens to the beneficiary, and a `Transfer` log says so. Nobody can emit that without
 *      actually moving the tokens, which removes the source-side trust assumption entirely
 *      rather than narrowing it.
 *
 *      A `Transfer` log carries no job identifier, so a delivery job is found by the triple
 *      the log does carry: the token, the sender and the recipient. The escrow reserves that
 *      triple when the job is created, so exactly one job can ever match a given log.
 */
contract SourceRegistry {
    /// @notice How a log from this emitter identifies the job it settles.
    enum Kind {
        /// @dev A purpose-built oracle whose event names the job.
        Attested,
        /// @dev An ordinary token whose Transfer is itself the acceptance criterion.
        Delivery
    }

    /// @notice Registered shape of one source-chain emitter.
    struct Source {
        bool registered;
        Kind kind;
        uint64 chainKey; // Attestcoin chain key (Ethereum Sepolia == 1 on CC3 Testnet).
        uint64 evmChainId; // EVM chain id of that chain (Sepolia == 11155111).
        bytes32 topic0Completed; // success signature, or Transfer for a Delivery source.
        bytes32 topic0Failed; // failure signature. Unused by Delivery sources.
        uint8 completedJobIdTopic; // Attested: topics[] index holding jobId.
        uint8 completedCriteriaTopic; // Attested: topics[] index holding criteriaHash.
        uint8 completedBuilderTopic; // Attested: topics[] index holding builder.
        uint8 failedJobIdTopic; // Attested: topics[] index holding jobId on failure.
        uint8 completedTopicCount; // exact expected topics[] length for success/Transfer.
        uint8 failedTopicCount; // exact expected topics[] length for failure.
        uint8 deliveryFromTopic; // Delivery: topics[] index holding the sender.
        uint8 deliveryToTopic; // Delivery: topics[] index holding the recipient.
    }

    error NotOwner();
    error ZeroAddress();
    error AlreadyRegistered(address emitter);
    error NotRegistered(address emitter);
    error InvalidTopicLayout();

    /// @notice Address allowed to add or remove sources.
    address public owner;

    /// @notice Source-chain emitter address => its registered shape.
    mapping(address => Source) private _sources;

    /// @notice Emitted when a source-chain emitter becomes trusted.
    event SourceRegistered(address indexed emitter, uint64 indexed chainKey, uint64 evmChainId, Kind kind);
    /// @notice Emitted when a source-chain emitter is removed.
    event SourceRemoved(address indexed emitter);
    /// @notice Emitted on ownership handover.
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

    /// @notice Hand the registry to a new owner.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Trust a source-chain emitter and record how to read its events.
    /// @dev Reverts if the emitter is already registered; an update means remove then re-add,
    ///      so a silent redefinition can never change how existing jobs settle.
    function registerSource(address emitter, Source calldata source) external onlyOwner {
        if (emitter == address(0)) revert ZeroAddress();
        if (_sources[emitter].registered) revert AlreadyRegistered(emitter);
        if (source.topic0Completed == bytes32(0)) revert InvalidTopicLayout();
        // Topic 0 is always the event signature, so no field may claim it, and a log carries
        // at most four topics.
        if (source.completedTopicCount == 0 || source.completedTopicCount > 4) {
            revert InvalidTopicLayout();
        }

        if (source.kind == Kind.Attested) {
            if (source.topic0Failed == bytes32(0)) revert InvalidTopicLayout();
            if (source.topic0Completed == source.topic0Failed) revert InvalidTopicLayout();
            if (source.failedTopicCount == 0 || source.failedTopicCount > 4) {
                revert InvalidTopicLayout();
            }
            if (
                source.completedJobIdTopic == 0 || source.completedCriteriaTopic == 0
                    || source.completedBuilderTopic == 0 || source.failedJobIdTopic == 0
                    || source.completedJobIdTopic >= source.completedTopicCount
                    || source.completedCriteriaTopic >= source.completedTopicCount
                    || source.completedBuilderTopic >= source.completedTopicCount
                    || source.failedJobIdTopic >= source.failedTopicCount
            ) revert InvalidTopicLayout();
        } else {
            // A Delivery source has no failure event and no job id in the log. It needs the
            // sender and recipient positions, and nothing else.
            if (
                source.deliveryFromTopic == 0 || source.deliveryToTopic == 0
                    || source.deliveryFromTopic == source.deliveryToTopic
                    || source.deliveryFromTopic >= source.completedTopicCount
                    || source.deliveryToTopic >= source.completedTopicCount
            ) revert InvalidTopicLayout();
        }

        Source memory s = source;
        s.registered = true;
        _sources[emitter] = s;

        emit SourceRegistered(emitter, s.chainKey, s.evmChainId, s.kind);
    }

    /// @notice Stop trusting a source-chain emitter.
    function removeSource(address emitter) external onlyOwner {
        if (!_sources[emitter].registered) revert NotRegistered(emitter);
        delete _sources[emitter];
        emit SourceRemoved(emitter);
    }

    /// @notice Read a registered source, reverting if the emitter is unknown.
    function requireSource(address emitter) external view returns (Source memory source) {
        source = _sources[emitter];
        if (!source.registered) revert NotRegistered(emitter);
    }

    /// @notice Read a source without reverting.
    function getSource(address emitter) external view returns (Source memory source) {
        return _sources[emitter];
    }

    /// @notice Whether an emitter is trusted.
    function isRegistered(address emitter) external view returns (bool) {
        return _sources[emitter].registered;
    }
}
