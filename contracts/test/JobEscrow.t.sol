// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Base} from "./Base.t.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {SourceRegistry} from "../src/SourceRegistry.sol";
import {ProvedTx} from "./harness/ProvedTx.sol";

/// @notice The release path and the six gates that guard it.
/// @dev Test names are claims, not chores: each one states a property the escrow must have.
contract JobEscrowTest is Base {
    // ------------------------------------------------------------ happy path

    function test_release_paysBuilderAndReturnsBond_whenCompletionIsProved() public {
        _openFundedJob();
        uint256 before = token.balanceOf(builder);

        _release(stranger, _goodCompletedTx(), 1);

        assertEq(token.balanceOf(builder) - before, uint256(AMOUNT) + BOND, "builder paid amount + bond");
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Released));
        assertEq(token.balanceOf(address(escrow)), 0, "vault drained to zero");
        assertTrue(escrow.vaultSolvent());
    }

    function test_release_canBeSubmittedByAnyone_notJustTheBuilder() public {
        _openFundedJob();
        // A relayer with no stake in the job carries the proof; the money still goes
        // to the builder named in the proved event, never to the submitter.
        uint256 relayerBefore = token.balanceOf(stranger);
        _release(stranger, _goodCompletedTx(), 1);
        assertEq(token.balanceOf(stranger), relayerBefore, "submitter is paid nothing");
    }

    // -------------------------------------------------------------- GATE 1

    /// @dev The single most important test in this repo. The precompile proves a
    ///      transaction was INCLUDED in a block. A reverted transaction is included too.
    ///      Without this gate a builder calls WorkCompleted, lets it revert, proves the
    ///      inclusion honestly, and is paid for work that never happened.
    function test_release_isRefused_whenReceiptStatusIsZero() public {
        _openFundedJob();
        bytes memory reverted =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 0, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, builder)));

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.ReceiptNotSuccessful.selector, uint8(0)));
        _release(stranger, reverted, 1);

        assertEq(token.balanceOf(address(escrow)), uint256(AMOUNT) + BOND, "funds untouched");
    }

    function test_release_isRefused_whenPrecompileRejectsTheProof() public {
        _openFundedJob();
        _rejectProofs();

        vm.expectRevert("Proof of inclusion verification failed");
        _release(stranger, _goodCompletedTx(), 1);
    }

    // -------------------------------------------------------------- GATE 2

    function test_release_isRefused_whenEmitterIsNotRegistered() public {
        _openFundedJob();
        address impostor = makeAddr("impostorOracle");
        // A perfectly well-formed WorkCompleted, honestly proved, from a contract the
        // registry never heard of. This is the attack the registry exists to stop.
        bytes memory forged =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(impostor, JOB, CRITERIA, builder)));

        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, forged, 1);
    }

    /// @dev Identical bytecode deployed from an identical nonce lands on an identical
    ///      address on every EVM chain. Without a chain-id check, the registered address
    ///      is not enough to pin down which chain the event came from.
    function test_release_isRefused_whenProvedChainIdIsNotTheRegisteredChain() public {
        _openFundedJob();
        bytes memory wrongChain =
            ProvedTx.type2(MAINNET_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, builder)));

        vm.expectRevert(
            abi.encodeWithSelector(JobEscrow.SourceChainMismatch.selector, SEPOLIA_CHAIN_ID, MAINNET_CHAIN_ID)
        );
        _release(stranger, wrongChain, 1);
    }

    // -------------------------------------------------------------- GATE 3

    function test_release_isRefused_whenTopic0IsNotWorkCompleted() public {
        _openFundedJob();
        // A WorkFailed log submitted down the release path must not settle anything.
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, _goodFailedTx(), 1);
    }

    function test_release_isRefused_whenTopicCountIsWrong() public {
        _openFundedJob();
        bytes32[] memory topics = new bytes32[](3); // one topic short
        topics[0] = TOPIC_COMPLETED;
        topics[1] = JOB;
        topics[2] = CRITERIA;
        ProvedTx.Log memory truncated =
            ProvedTx.Log({emitter: sourceOracle, topics: topics, data: abi.encode(bytes32(0))});

        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(truncated)), 1);
    }

    // -------------------------------------------------------------- GATE 4

    function test_release_isRefused_whenCriteriaHashDiffersFromTheFrozenOne() public {
        _openFundedJob();
        bytes32 moved = keccak256("criteria-v2-moved-goalposts");
        bytes memory tx_ =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, JOB, moved, builder)));

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.CriteriaMismatch.selector, JOB, CRITERIA, moved));
        _release(stranger, tx_, 1);
    }

    function test_release_isRefused_whenBuilderInTopicIsNotTheJobBuilder() public {
        _openFundedJob();
        bytes memory tx_ =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, stranger)));

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.BuilderMismatch.selector, JOB, builder, stranger));
        _release(stranger, tx_, 1);
    }

    function test_release_isRefused_whenJobIdMatchesNoJob() public {
        _openFundedJob();
        bytes32 ghost = keccak256("job-that-never-existed");
        bytes memory tx_ =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, ghost, CRITERIA, builder)));

        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongStatus.selector, ghost, JobEscrow.Status.None, JobEscrow.Status.Funded
            )
        );
        _release(stranger, tx_, 1);
    }

    function test_release_isRefused_whenJobIsCreatedButNotYetFunded() public {
        vm.prank(buyer);
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);

        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongStatus.selector, JOB, JobEscrow.Status.Created, JobEscrow.Status.Funded
            )
        );
        _release(stranger, _goodCompletedTx(), 1);
    }

    // -------------------------------------------------------------- GATE 6

    function test_release_isRefused_afterDeadline() public {
        _openFundedJob();
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.DeadlinePassed.selector, JOB, deadline));
        _release(stranger, _goodCompletedTx(), 1);
    }

    function test_release_isAccepted_atExactlyTheDeadline() public {
        _openFundedJob();
        vm.warp(deadline);
        _release(stranger, _goodCompletedTx(), 1);
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Released));
    }

    /// @dev The release window and the refund window must never both be open, or the
    ///      builder and the buyer would be racing on transaction ordering for the money.
    function test_releaseAndRefundWindows_neverOverlap() public {
        _openFundedJob();

        vm.warp(deadline); // last instant release is legal
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.DeadlineNotReached.selector, JOB, deadline));
        escrow.refund(JOB);

        vm.warp(deadline + 1); // first instant refund is legal
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.DeadlinePassed.selector, JOB, deadline));
        _release(stranger, _goodCompletedTx(), 1);

        escrow.refund(JOB); // and it does open
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Refunded));
    }

    // ------------------------------------------------------- transaction types

    function test_release_acceptsLegacyEip155Transaction() public {
        _openFundedJob();
        bytes memory legacy =
            ProvedTx.type0(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, builder)));
        _release(stranger, legacy, 1);
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Released));
    }

    function test_release_isRefused_whenLegacyTxPredatesEip155() public {
        _openFundedJob();
        // v = 27 carries no chain id, so the transaction cannot be pinned to a chain.
        bytes memory ancient =
            ProvedTx.type0PreEip155(1, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, builder)));

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.UnsupportedTxType.selector, uint8(0)));
        _release(stranger, ancient, 1);
    }

    function test_release_isRefused_whenTransactionTypeIsUnsupported() public {
        _openFundedJob();
        bytes memory blobTx = ProvedTx.type3(1, ProvedTx.one(_completedLog(sourceOracle, JOB, CRITERIA, builder)));

        vm.expectRevert(abi.encodeWithSelector(JobEscrow.UnsupportedTxType.selector, uint8(3)));
        _release(stranger, blobTx, 1);
    }

    function test_execute_isRefused_whenActionIsUnknown() public {
        _openFundedJob();
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.InvalidAction.selector, uint8(7)));
        _submit(stranger, 7, _goodCompletedTx(), 1);
    }

    // ----------------------------------------------------------------- setup

    function test_createJob_isRefused_whenSourceIsNotRegistered() public {
        address unknown = makeAddr("unknownOracle");
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(SourceRegistry.NotRegistered.selector, unknown));
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, unknown);
    }

    function test_createJob_isRefused_whenDeadlineIsInThePast() public {
        vm.prank(buyer);
        vm.expectRevert(JobEscrow.InvalidDeadline.selector);
        escrow.createJob(JOB, builder, AMOUNT, uint64(block.timestamp), CRITERIA, sourceOracle);
    }

    function test_createJob_isRefused_whenJobIdIsTaken() public {
        vm.startPrank(buyer);
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.JobAlreadyExists.selector, JOB));
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);
        vm.stopPrank();
    }

    function test_fundJob_isRefused_beforeTheBondIsPosted() public {
        vm.prank(buyer);
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.BondNotPosted.selector, JOB));
        escrow.fundJob(JOB);
    }

    function test_postBond_isRefused_whenCallerIsNotTheBuilder() public {
        vm.prank(buyer);
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.NotBuilder.selector, JOB));
        escrow.postBond(JOB);
    }

    function test_fundJob_isRefused_whenCallerIsNotTheBuyer() public {
        vm.prank(buyer);
        escrow.createJob(JOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle);
        vm.prank(builder);
        escrow.postBond(JOB);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.NotBuyer.selector, JOB));
        escrow.fundJob(JOB);
    }

    // ---------------------------------------------------------------- refund

    function test_refund_isRefused_beforeDeadline() public {
        _openFundedJob();
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.DeadlineNotReached.selector, JOB, deadline));
        escrow.refund(JOB);
    }

    function test_refund_returnsAmountAndBondToBuyer_afterDeadline() public {
        _openFundedJob();
        uint256 before = token.balanceOf(buyer);
        vm.warp(deadline + 1);

        escrow.refund(JOB);

        assertEq(token.balanceOf(buyer) - before, uint256(AMOUNT) + BOND);
        assertEq(uint8(escrow.getJob(JOB).status), uint8(JobEscrow.Status.Refunded));
    }

    function test_refund_isRefused_twice() public {
        _openFundedJob();
        vm.warp(deadline + 1);
        escrow.refund(JOB);

        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongStatus.selector, JOB, JobEscrow.Status.Refunded, JobEscrow.Status.Funded
            )
        );
        escrow.refund(JOB);
    }

    // ------------------------------------------------------------ no admin

    /// @dev The escrow has no owner, no pause, no upgrade path and no sweep. The only
    ///      code that can move a user's tokens is the four settlement paths above.
    function test_escrow_hasNoAdminAbleToTouchUserFunds() public {
        _openFundedJob();
        uint256 locked = token.balanceOf(address(escrow));

        // The registry owner is the most privileged address in the system. Even removing
        // the source afterwards moves nothing and cannot reach into the vault.
        registry.removeSource(sourceOracle);
        assertEq(token.balanceOf(address(escrow)), locked, "registry owner cannot move escrowed funds");

        // And no arbitrary call finds a withdraw entry point.
        (bool ok,) = address(escrow).call(abi.encodeWithSignature("withdraw(address,uint256)", stranger, locked));
        assertFalse(ok, "no withdraw function exists");
        (ok,) = address(escrow).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "no owner function exists");
        assertEq(token.balanceOf(address(escrow)), locked);
    }

    function test_registry_isRefused_whenCallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(SourceRegistry.NotOwner.selector);
        registry.registerSource(makeAddr("x"), _sepoliaSource());
    }
}
