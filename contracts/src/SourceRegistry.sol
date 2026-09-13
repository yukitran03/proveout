// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/**
 * @title SourceRegistry
 * @notice The list of source-chain emitters ProveOut is willing to believe, and the exact
 *         shape of their events.
 *
 * @dev This is the contract that makes a proof mean something. The Attestcoin precompile
 *      proves that a transaction was included in a source-chain block — it does not and
 *      cannot know whether the contract that emitted a log inside it is one you trust.
 *      Without this registry, anyone could deploy their own contract on Sepolia, emit a
 *      perfectly-formed `WorkCompleted`, prove it honestly, and drain every escrow.
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
 */
contract SourceRegistry {
    /// @notice Registered shape of one source-chain emitter.
    struct Source {
        bool registered;
        uint64 chainKey; // Attestcoin chain key (Ethereum Sepolia == 1 on CC3 Testnet).
        uint64 evmChainId; // EVM chain id of that chain (Sepolia == 11155111).
        bytes32 topic0Completed; // keccak256 of the success event signature.
        bytes32 topic0Failed; // keccak256 of the failure event signature.
        uint8 completedJobIdTopic; // index into topics[] holding jobId.
        uint8 completedCriteriaTopic; // index into topics[] holding criteriaHash.
        uint8 completedBuilderTopic; // index into topics[] holding builder.
        uint8 failedJobIdTopic; // index into topics[] holding jobId on failure.
        uint8 completedTopicCount; // exact expected topics[] length for success.
        uint8 failedTopicCount; // exact expected topics[] length for failure.
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
    event SourceRegistered(address indexed emitter, uint64 indexed chainKey, uint64 evmChainId);
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
    /// @dev Reverts if the emitter is already registered; update means remove then re-add,
    ///      so a silent redefinition can never change how existing jobs are settled.
    function registerSource(address emitter, Source calldata source) external onlyOwner {
        if (emitter == address(0)) revert ZeroAddress();
        if (_sources[emitter].registered) revert AlreadyRegistered(emitter);
        if (source.topic0Completed == bytes32(0) || source.topic0Failed == bytes32(0)) {
            revert InvalidTopicLayout();
        }
        if (source.topic0Completed == source.topic0Failed) revert InvalidTopicLayout();
        // Topic 0 is always the event signature, so no field may claim it, and a log
        // carries at most four topics.
        if (
            source.completedJobIdTopic == 0 || source.completedJobIdTopic > 3
                || source.completedCriteriaTopic == 0 || source.completedCriteriaTopic > 3
                || source.completedBuilderTopic == 0 || source.completedBuilderTopic > 3
                || source.failedJobIdTopic == 0 || source.failedJobIdTopic > 3
                || source.completedTopicCount == 0 || source.completedTopicCount > 4
                || source.failedTopicCount == 0 || source.failedTopicCount > 4
                || source.completedJobIdTopic >= source.completedTopicCount
                || source.completedCriteriaTopic >= source.completedTopicCount
                || source.completedBuilderTopic >= source.completedTopicCount
                || source.failedJobIdTopic >= source.failedTopicCount
        ) revert InvalidTopicLayout();

        Source memory s = source;
        s.registered = true;
        _sources[emitter] = s;

        emit SourceRegistered(emitter, s.chainKey, s.evmChainId);
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
