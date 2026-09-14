// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {JobEscrow} from "../src/JobEscrow.sol";
import {SourceRegistry} from "../src/SourceRegistry.sol";
import {TestUSDC} from "../src/TestUSDC.sol";
import {WorkOracle} from "../src/WorkOracle.sol";
import {ProvedTx, MockBlockProver, RejectingBlockProver} from "./harness/ProvedTx.sol";

/// @notice Shared world for every ProveOut test.
abstract contract Base is Test {
    /// @dev Verified against docs.attestcoin.org and confirmed live in spikes/spike1_prove.ts.
    address internal constant PRECOMPILE = 0x0000000000000000000000000000000000000FD2;
    uint64 internal constant SEPOLIA_CHAIN_KEY = 1;
    uint64 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint64 internal constant MAINNET_CHAIN_ID = 1;

    bytes32 internal constant TOPIC_COMPLETED = keccak256("WorkCompleted(bytes32,bytes32,address,bytes32)");
    bytes32 internal constant TOPIC_FAILED = keccak256("WorkFailed(bytes32,bytes32)");

    uint16 internal constant BOND_BPS = 2_000; // 20%
    uint16 internal constant BOUNTY_BPS = 5_000; // 50% of the bond

    TestUSDC internal token;
    SourceRegistry internal registry;
    JobEscrow internal escrow;

    address internal buyer = makeAddr("buyer");
    address internal builder = makeAddr("builder");
    address internal challenger = makeAddr("challenger");
    address internal stranger = makeAddr("stranger");
    /// @dev Stands in for the WorkOracle deployed on Sepolia.
    address internal sourceOracle = makeAddr("sourceOracle");

    bytes32 internal constant JOB = keccak256("job-1");
    bytes32 internal constant CRITERIA = keccak256("criteria-v1");
    uint128 internal constant AMOUNT = 1_000e6; // 1,000 tUSDC
    uint128 internal constant BOND = 200e6; // 20% of AMOUNT
    uint64 internal deadline;

    function setUp() public virtual {
        vm.warp(1_757_700_000); // fixed clock so deadline maths is readable
        deadline = uint64(block.timestamp + 7 days);

        vm.etch(PRECOMPILE, address(new MockBlockProver()).code);

        token = new TestUSDC();
        registry = new SourceRegistry();
        escrow = new JobEscrow(token, registry, BOND_BPS, BOUNTY_BPS);

        registry.registerSource(sourceOracle, _sepoliaSource());

        token.mint(buyer, 1_000_000e6);
        token.mint(builder, 1_000_000e6);
        vm.prank(buyer);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(builder);
        token.approve(address(escrow), type(uint256).max);
    }

    // ------------------------------------------------------------- fixtures

    function _sepoliaSource() internal pure returns (SourceRegistry.Source memory) {
        return SourceRegistry.Source({
            registered: false,
            kind: SourceRegistry.Kind.Attested, // set by the registry itself
            chainKey: SEPOLIA_CHAIN_KEY,
            evmChainId: SEPOLIA_CHAIN_ID,
            topic0Completed: TOPIC_COMPLETED,
            topic0Failed: TOPIC_FAILED,
            completedJobIdTopic: 1,
            completedCriteriaTopic: 2,
            completedBuilderTopic: 3,
            failedJobIdTopic: 1,
            completedTopicCount: 4,
            failedTopicCount: 3,
            deliveryFromTopic: 0,
            deliveryToTopic: 0
        });
    }

    /// @dev A `WorkCompleted` log exactly as WorkOracle emits it on Sepolia.
    function _completedLog(address emitter, bytes32 jobId, bytes32 criteria, address who)
        internal
        pure
        returns (ProvedTx.Log memory)
    {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = TOPIC_COMPLETED;
        topics[1] = jobId;
        topics[2] = criteria;
        topics[3] = bytes32(uint256(uint160(who)));
        return ProvedTx.Log({emitter: emitter, topics: topics, data: abi.encode(keccak256("output"))});
    }

    /// @dev A `WorkFailed` log exactly as WorkOracle emits it on Sepolia.
    function _failedLog(address emitter, bytes32 jobId) internal pure returns (ProvedTx.Log memory) {
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = TOPIC_FAILED;
        topics[1] = jobId;
        topics[2] = keccak256("criteria-not-met");
        return ProvedTx.Log({emitter: emitter, topics: topics, data: bytes("")});
    }

    function _goodCompletedTx() internal view returns (bytes memory) {
        return ProvedTx.type2(
            SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, builder))
        );
    }

    function _goodFailedTx() internal view returns (bytes memory) {
        return ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_failedLog(sourceOracle, JOB)));
    }

    // -------------------------------------------------------------- actions

    /// @dev Drive a job to `Funded`.
    function _openFundedJob() internal {
        vm.prank(buyer);
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);
        vm.prank(builder);
        escrow.postBond(JOB);
        vm.prank(buyer);
        escrow.fundJob(JOB);
    }

    /// @dev Submit a proof through the canonical ASCBase entry point.
    /// @param seed Varies the Merkle root, and therefore the protocol query id.
    function _submit(address caller, uint8 action, bytes memory encodedTx, uint256 seed) internal {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: keccak256("sib"), isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = keccak256("continuity");

        vm.prank(caller);
        escrow.execute(
            action,
            SEPOLIA_CHAIN_KEY,
            uint64(11_689_820 + seed),
            encodedTx,
            bytes32(seed),
            siblings,
            keccak256("lower"),
            roots
        );
    }

    function _release(address caller, bytes memory encodedTx, uint256 seed) internal {
        _submit(caller, 0, encodedTx, seed);
    }

    function _challenge(address caller, bytes memory encodedTx, uint256 seed) internal {
        _submit(caller, 1, encodedTx, seed);
    }

    function _rejectProofs() internal {
        vm.etch(PRECOMPILE, address(new RejectingBlockProver()).code);
    }
}
