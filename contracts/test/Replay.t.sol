// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Base} from "./Base.t.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {ProvedTx} from "./harness/ProvedTx.sol";

/// @notice Replay protection.
/// @dev ProveOut does not roll its own nullifier. {ASCBase} already refuses a query id it
///      has seen, where the id is `keccak256(chainKey, blockHeight, txIndex)` and the
///      transaction index is derived by the precompile from the verified Merkle path, not
///      supplied by the caller. These tests pin that behaviour down as ours, because a
///      dependency's guarantee is only a guarantee while it is tested.
contract ReplayTest is Base {
    function test_replay_isRefused_whenTheSameProofIsSubmittedTwice() public {
        _openFundedJob();
        bytes memory proofTx = _goodCompletedTx();

        _release(stranger, proofTx, 1);

        vm.expectRevert("Query already processed");
        _release(stranger, proofTx, 1);
    }

    function test_replay_isRefused_evenWhenADifferentAddressResubmits() public {
        _openFundedJob();
        _release(stranger, _goodCompletedTx(), 1);

        vm.expectRevert("Query already processed");
        _release(challenger, _goodCompletedTx(), 1);
    }

    /// @dev One proved completion must not unlock a second, unrelated escrow. The job id
    ///      lives inside the proved log, so pointing the same proof at another job simply
    ///      settles the job the log names, and only once.
    function test_oneProof_cannotSettleASecondJob() public {
        _openFundedJob();

        bytes32 job2 = keccak256("job-2");
        vm.prank(buyer);
        escrow.createJob(job2, builder, AMOUNT, deadline, CRITERIA, sourceOracle);
        vm.prank(builder);
        escrow.postBond(job2);
        vm.prank(buyer);
        escrow.fundJob(job2);

        bytes memory proofTx = _goodCompletedTx(); // names JOB, not job2
        _release(stranger, proofTx, 1);

        vm.expectRevert("Query already processed");
        _release(stranger, proofTx, 1);

        assertEq(uint8(escrow.getJob(job2).status), uint8(JobEscrow.Status.Funded), "job-2 still locked");
        assertEq(token.balanceOf(address(escrow)), uint256(AMOUNT) + BOND, "job-2 funds still held");
    }

    function test_replay_isRefused_acrossTheReleaseAndChallengePaths() public {
        _openFundedJob();
        // Same query id, other action: the base layer refuses before any app logic runs.
        _challenge(challenger, _goodFailedTx(), 1);

        vm.expectRevert("Query already processed");
        _submit(stranger, 0, _goodCompletedTx(), 1);
    }

    function test_distinctProofs_settleDistinctJobs() public {
        _openFundedJob();

        bytes32 job2 = keccak256("job-2");
        vm.prank(buyer);
        escrow.createJob(job2, builder, AMOUNT, deadline, CRITERIA, sourceOracle);
        vm.prank(builder);
        escrow.postBond(job2);
        vm.prank(buyer);
        escrow.fundJob(job2);

        _release(stranger, _goodCompletedTx(), 1);
        _release(
            stranger,
            ProvedTx.type2(
                SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, job2, CRITERIA, builder))
            ),
            2
        );

        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Released));
        assertEq(uint8(escrow.getJob(job2).status), uint8(JobEscrow.Status.Released));
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_processedQueries_isRecordedOnTheEscrow() public {
        _openFundedJob();
        _release(stranger, _goodCompletedTx(), 1);
        // queryId = keccak256(chainKey, blockHeight, txIndex); the mock derives txIndex
        // from the Merkle root exactly as the precompile derives it from the proof path.
        bytes32 queryId = _expectedQueryId(SEPOLIA_CHAIN_KEY, uint64(11_689_820 + 1), uint64(1));
        assertTrue(escrow.processedQueries(queryId), "query id burned");
    }

    function _expectedQueryId(uint64 chainKey, uint64 height, uint64 txIndex) private pure returns (bytes32 id) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, chainKey)
            mstore(add(ptr, 32), shl(192, height))
            mstore(add(ptr, 40), txIndex)
            id := keccak256(ptr, 72)
        }
    }
}
