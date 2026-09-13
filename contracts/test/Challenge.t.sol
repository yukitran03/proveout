// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Base} from "./Base.t.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {ProvedTx} from "./harness/ProvedTx.sol";

/// @notice Adversarial evidence: the property that separates ProveOut from designs where
///         only the party who benefits ever submits proof.
contract ChallengeTest is Base {
    /// @dev The headline claim. Not the buyer, not the builder, not an arbiter, not an
    ///      allowlisted relayer. Any address at all can end this escrow by proving failure.
    function test_anyone_canForceRefund_withFailureProof() public {
        _openFundedJob();
        uint256 buyerBefore = token.balanceOf(buyer);
        uint256 challengerBefore = token.balanceOf(challenger);

        _challenge(challenger, _goodFailedTx(), 1);

        uint128 bounty = uint128((uint256(BOND) * BOUNTY_BPS) / 10_000);
        assertEq(token.balanceOf(buyer) - buyerBefore, uint256(AMOUNT) + (BOND - bounty), "buyer made whole");
        assertEq(token.balanceOf(challenger) - challengerBefore, bounty, "challenger paid the bounty");
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Refunded));
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    /// @dev Reporting failure has to pay, or nobody does it. The bounty comes out of the
    ///      builder's own bond, so the cost of being caught falls on the party that failed.
    function test_challengeBounty_isPaidOutOfTheBuildersBond_notTheBuyersMoney() public {
        _openFundedJob();
        uint256 buyerBefore = token.balanceOf(buyer);

        _challenge(challenger, _goodFailedTx(), 1);

        // The buyer never loses a micro-unit of the escrowed payout; the bounty is carved
        // strictly out of the bond.
        assertGe(token.balanceOf(buyer) - buyerBefore, uint256(AMOUNT), "payout returned in full");
    }

    /// @dev If the challenge window closed with the release window, hiding a failure until
    ///      the deadline passed would be a winning strategy. It stays open forever.
    function test_challenge_stillWorks_afterTheDeadline() public {
        _openFundedJob();
        vm.warp(deadline + 365 days);

        _challenge(challenger, _goodFailedTx(), 1);
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Refunded));
    }

    function test_challenge_isRefused_whenReceiptStatusIsZero() public {
        _openFundedJob();
        bytes memory reverted = ProvedTx.type2(SEPOLIA_CHAIN_ID, 0, ProvedTx.one(_failedLog(sourceOracle, JOB)));

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.ReceiptNotSuccessful.selector, uint8(0)));
        _challenge(challenger, reverted, 1);
    }

    function test_challenge_isRefused_whenEmitterIsNotRegistered() public {
        _openFundedJob();
        // Anyone can emit a WorkFailed from their own contract; griefing an honest builder
        // has to be impossible or the bond is not safe to post.
        bytes memory forged =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_failedLog(makeAddr("griefer"), JOB)));

        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _challenge(challenger, forged, 1);
    }

    function test_challenge_isRefused_whenProvedChainIdIsWrong() public {
        _openFundedJob();
        bytes memory wrongChain =
            ProvedTx.type2(MAINNET_CHAIN_ID, 1, ProvedTx.one(_failedLog(sourceOracle, JOB)));

        vm.expectRevert(
            abi.encodeWithSelector(JobEscrow.SourceChainMismatch.selector, SEPOLIA_CHAIN_ID, MAINNET_CHAIN_ID)
        );
        _challenge(challenger, wrongChain, 1);
    }

    function test_challenge_isRefused_afterTheJobWasAlreadyReleased() public {
        _openFundedJob();
        _release(stranger, _goodCompletedTx(), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongStatus.selector, JOB, JobEscrow.Status.Released, JobEscrow.Status.Funded
            )
        );
        _challenge(challenger, _goodFailedTx(), 2);
    }

    function test_challenge_isRefused_whenCompletionProofIsSentDownTheFailurePath() public {
        _openFundedJob();
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _challenge(challenger, _goodCompletedTx(), 1);
    }

    /// @dev The race that matters: a builder's release and a challenger's failure proof
    ///      land in the same block. Whichever is mined first wins outright; the loser
    ///      reverts rather than double-spending the vault.
    function test_releaseAndChallenge_cannotBothSettleTheSameJob() public {
        _openFundedJob();
        _challenge(challenger, _goodFailedTx(), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongStatus.selector, JOB, JobEscrow.Status.Refunded, JobEscrow.Status.Funded
            )
        );
        _release(stranger, _goodCompletedTx(), 2);

        assertTrue(escrow.vaultSolvent());
    }
}
