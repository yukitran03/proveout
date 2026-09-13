// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {JobEscrow} from "../src/JobEscrow.sol";
import {SourceRegistry} from "../src/SourceRegistry.sol";
import {TestUSDC} from "../src/TestUSDC.sol";
import {ProvedTx, MockBlockProver} from "./harness/ProvedTx.sol";

/// @notice Drives the escrow through random orderings of every state-changing path.
contract EscrowHandler is Test {
    JobEscrow public escrow;
    TestUSDC public token;
    address public sourceOracle;

    bytes32 internal constant TOPIC_COMPLETED = keccak256("WorkCompleted(bytes32,bytes32,address,bytes32)");
    bytes32 internal constant TOPIC_FAILED = keccak256("WorkFailed(bytes32,bytes32)");
    uint64 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint64 internal constant SEPOLIA_CHAIN_KEY = 1;

    bytes32[] public jobIds;
    mapping(bytes32 => bytes32) public criteriaOf;
    uint256 public proofNonce;

    constructor(JobEscrow escrow_, TestUSDC token_, address sourceOracle_) {
        escrow = escrow_;
        token = token_;
        sourceOracle = sourceOracle_;
        token.mint(address(this), type(uint128).max);
        token.approve(address(escrow), type(uint256).max);
    }

    function createJob(uint96 rawAmount, uint32 rawWindow) external {
        uint128 amount = uint128(bound(rawAmount, 1, 1_000_000e6));
        uint64 window = uint64(bound(rawWindow, 1, 30 days));
        bytes32 jobId = keccak256(abi.encode("job", jobIds.length, block.timestamp));
        bytes32 criteria = keccak256(abi.encode("criteria", jobId));

        try escrow.createJob(jobId, address(this), amount, uint64(block.timestamp) + window, criteria, sourceOracle)
        {
            jobIds.push(jobId);
            criteriaOf[jobId] = criteria;
        } catch {}
    }

    function postBond(uint256 seed) external {
        if (jobIds.length == 0) return;
        try escrow.postBond(jobIds[seed % jobIds.length]) {} catch {}
    }

    function fundJob(uint256 seed) external {
        if (jobIds.length == 0) return;
        try escrow.fundJob(jobIds[seed % jobIds.length]) {} catch {}
    }

    function release(uint256 seed) external {
        if (jobIds.length == 0) return;
        bytes32 jobId = jobIds[seed % jobIds.length];
        _submit(0, _encode(TOPIC_COMPLETED, jobId, criteriaOf[jobId], 4), 1);
    }

    function challenge(uint256 seed) external {
        if (jobIds.length == 0) return;
        bytes32 jobId = jobIds[seed % jobIds.length];
        _submit(1, _encode(TOPIC_FAILED, jobId, keccak256("reason"), 3), 1);
    }

    function refund(uint256 seed) external {
        if (jobIds.length == 0) return;
        try escrow.refund(jobIds[seed % jobIds.length]) {} catch {}
    }

    function warp(uint32 rawJump) external {
        vm.warp(block.timestamp + bound(rawJump, 1 hours, 45 days));
    }

    /// @dev A stranger pushing tokens straight into the vault. The escrow must survive it:
    ///      this is exactly why the balance invariant is an inequality and not an equality.
    function donate(uint96 rawAmount) external {
        uint256 amount = bound(rawAmount, 1, 1_000e6);
        token.transfer(address(escrow), amount);
    }

    function _encode(bytes32 topic0, bytes32 jobId, bytes32 third, uint256 topicCount)
        private
        view
        returns (bytes memory)
    {
        bytes32[] memory topics = new bytes32[](topicCount);
        topics[0] = topic0;
        topics[1] = jobId;
        topics[2] = third;
        if (topicCount == 4) topics[3] = bytes32(uint256(uint160(address(this))));
        return ProvedTx.type2(
            SEPOLIA_CHAIN_ID,
            1,
            ProvedTx.one(ProvedTx.Log({emitter: sourceOracle, topics: topics, data: abi.encode(bytes32(0))}))
        );
    }

    function _submit(uint8 action, bytes memory encodedTx, uint256) private {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: keccak256("sib"), isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = keccak256("continuity");

        proofNonce++;
        try escrow.execute(
            action,
            SEPOLIA_CHAIN_KEY,
            uint64(11_000_000 + proofNonce),
            encodedTx,
            bytes32(proofNonce),
            siblings,
            keccak256("lower"),
            roots
        ) {} catch {}
    }

    function jobCount() external view returns (uint256) {
        return jobIds.length;
    }
}

/// @notice The one balance property the escrow must never break.
contract InvariantTest is Test {
    address internal constant PRECOMPILE = 0x0000000000000000000000000000000000000FD2;

    TestUSDC internal token;
    SourceRegistry internal registry;
    JobEscrow internal escrow;
    EscrowHandler internal handler;
    address internal sourceOracle = makeAddr("sourceOracle");

    function setUp() public {
        vm.warp(1_757_700_000);
        vm.etch(PRECOMPILE, address(new MockBlockProver()).code);

        token = new TestUSDC();
        registry = new SourceRegistry();
        escrow = new JobEscrow(token, registry, 2_000, 5_000);

        registry.registerSource(
            sourceOracle,
            SourceRegistry.Source({
                registered: false,
                chainKey: 1,
                evmChainId: 11_155_111,
                topic0Completed: keccak256("WorkCompleted(bytes32,bytes32,address,bytes32)"),
                topic0Failed: keccak256("WorkFailed(bytes32,bytes32)"),
                completedJobIdTopic: 1,
                completedCriteriaTopic: 2,
                completedBuilderTopic: 3,
                failedJobIdTopic: 1,
                completedTopicCount: 4,
                failedTopicCount: 3
            })
        );

        handler = new EscrowHandler(escrow, token, sourceOracle);
        targetContract(address(handler));
    }

    /// @dev `balance + paidOut >= takenIn`, never equality. An unsolicited transfer into
    ///      the vault raises the left-hand side and must never be able to wedge a payout.
    function invariant_vaultIsAlwaysSolvent() public view {
        assertTrue(escrow.vaultSolvent(), "vault insolvent");
    }

    /// @dev Everything that ever left the vault was settled through one of the four paths.
    function invariant_payoutsNeverExceedDeposits() public view {
        assertLe(escrow.totalOut(), escrow.totalIn(), "paid out more than was ever deposited");
    }
}
