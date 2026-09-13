// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {WorkOracle} from "../src/WorkOracle.sol";

/// @notice Who is allowed to state a job outcome on the source chain.
/// @dev These tests exist because the first version of this contract had none. Anyone
///      could emit a completion, which meant a builder could certify their own work and be
///      paid for it with proofs that were all perfectly genuine.
contract WorkOracleTest is Test {
    WorkOracle internal oracle;

    address internal platform = address(this);
    address internal builder = makeAddr("builder");
    address internal buyer = makeAddr("buyer");
    address internal stranger = makeAddr("stranger");
    address internal secondReporter = makeAddr("secondReporter");

    bytes32 internal constant JOB = keccak256("job-1");
    bytes32 internal constant CRITERIA = keccak256("criteria-v1");
    bytes32 internal constant OUTPUT = keccak256("output");
    bytes32 internal constant REASON = keccak256("criteria-not-met");

    event WorkCompleted(
        bytes32 indexed jobId, bytes32 indexed criteriaHash, address indexed builder, bytes32 outputHash
    );
    event WorkFailed(bytes32 indexed jobId, bytes32 indexed reason);
    event ReporterAdded(address indexed reporter);
    event ReporterRemoved(address indexed reporter);
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        oracle = new WorkOracle();
    }

    // ------------------------------------------------------ the bypass itself

    /// @dev The headline. Without this the entire escrow is decorative.
    function test_builder_cannotCertifyTheirOwnWork() public {
        vm.prank(builder);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.NotReporter.selector, builder));
        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
    }

    function test_buyer_cannotCertifyCompletionEither() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.NotReporter.selector, buyer));
        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
    }

    /// @dev An open failure path is a griefing primitive, not censorship resistance: it
    ///      lets a passer-by burn an honest builder's bond for the price of a transaction.
    function test_stranger_cannotBurnAnHonestBuildersBond() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.NotReporter.selector, stranger));
        oracle.reportFailed(JOB, REASON);
    }

    // ------------------------------------------------------- the allowed path

    function test_reporter_canReportCompletion() public {
        vm.expectEmit(true, true, true, true);
        emit WorkCompleted(JOB, CRITERIA, builder, OUTPUT);
        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
    }

    function test_reporter_canReportFailure() public {
        vm.expectEmit(true, true, false, true);
        emit WorkFailed(JOB, REASON);
        oracle.reportFailed(JOB, REASON);
    }

    function test_deployer_isTheFirstReporter() public view {
        assertTrue(oracle.isReporter(platform));
        assertEq(oracle.reporterCount(), 1);
        assertEq(oracle.owner(), platform);
    }

    function test_addedReporter_canReportImmediately() public {
        oracle.addReporter(secondReporter);
        vm.prank(secondReporter);
        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
        assertTrue(oracle.isReporter(secondReporter));
    }

    function test_removedReporter_canNoLongerReport() public {
        oracle.addReporter(secondReporter);
        oracle.removeReporter(secondReporter);

        vm.prank(secondReporter);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.NotReporter.selector, secondReporter));
        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
    }

    // ----------------------------------------------------------- reporter set

    function test_addReporter_isRefused_whenCallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(WorkOracle.NotOwner.selector);
        oracle.addReporter(stranger);
    }

    function test_addReporter_isRefused_forTheZeroAddress() public {
        vm.expectRevert(WorkOracle.ZeroAddress.selector);
        oracle.addReporter(address(0));
    }

    function test_addReporter_isRefused_whenAlreadyAuthorised() public {
        oracle.addReporter(secondReporter);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.AlreadyReporter.selector, secondReporter));
        oracle.addReporter(secondReporter);
    }

    function test_removeReporter_isRefused_whenCallerIsNotOwner() public {
        oracle.addReporter(secondReporter);
        vm.prank(stranger);
        vm.expectRevert(WorkOracle.NotOwner.selector);
        oracle.removeReporter(secondReporter);
    }

    function test_removeReporter_isRefused_forAnUnknownAddress() public {
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.UnknownReporter.selector, stranger));
        oracle.removeReporter(stranger);
    }

    /// @dev An oracle nobody can speak through strands every job that depends on it in the
    ///      deadline-refund path, and the builder loses a bond for a failure not theirs.
    function test_lastReporter_cannotBeRemoved() public {
        assertEq(oracle.reporterCount(), 1);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.UnknownReporter.selector, platform));
        oracle.removeReporter(platform);
        assertTrue(oracle.isReporter(platform));
    }

    function test_reporterCount_tracksAdditionsAndRemovals() public {
        assertEq(oracle.reporterCount(), 1);
        oracle.addReporter(secondReporter);
        assertEq(oracle.reporterCount(), 2);
        oracle.addReporter(stranger);
        assertEq(oracle.reporterCount(), 3);
        oracle.removeReporter(stranger);
        assertEq(oracle.reporterCount(), 2);
    }

    function test_addReporter_emitsReporterAdded() public {
        vm.expectEmit(true, false, false, true);
        emit ReporterAdded(secondReporter);
        oracle.addReporter(secondReporter);
    }

    function test_removeReporter_emitsReporterRemoved() public {
        oracle.addReporter(secondReporter);
        vm.expectEmit(true, false, false, true);
        emit ReporterRemoved(secondReporter);
        oracle.removeReporter(secondReporter);
    }

    // -------------------------------------------------------------- ownership

    function test_transferOwnership_movesControlOfTheReporterSet() public {
        oracle.transferOwnership(secondReporter);
        assertEq(oracle.owner(), secondReporter);

        vm.prank(secondReporter);
        oracle.addReporter(stranger);
        assertTrue(oracle.isReporter(stranger));
    }

    function test_transferOwnership_isRefused_whenCallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(WorkOracle.NotOwner.selector);
        oracle.transferOwnership(stranger);
    }

    function test_transferOwnership_isRefused_forTheZeroAddress() public {
        vm.expectRevert(WorkOracle.ZeroAddress.selector);
        oracle.transferOwnership(address(0));
    }

    /// @dev Ownership moves the ability to appoint reporters, not the ability to report.
    ///      The old owner keeps reporting only because it was separately a reporter.
    function test_formerOwner_losesTheReporterSetButKeepsItsOwnReporterRole() public {
        oracle.transferOwnership(secondReporter);

        vm.expectRevert(WorkOracle.NotOwner.selector);
        oracle.addReporter(stranger);

        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
    }

    // ------------------------------------------------------------- properties

    function testFuzz_onlyReportersCanReport(address caller) public {
        vm.assume(caller != platform);
        vm.assume(caller != address(0));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(WorkOracle.NotReporter.selector, caller));
        oracle.reportCompleted(JOB, CRITERIA, builder, OUTPUT);
    }

    function testFuzz_onlyOwnerCanAppointReporters(address caller) public {
        vm.assume(caller != platform);
        vm.prank(caller);
        vm.expectRevert(WorkOracle.NotOwner.selector);
        oracle.addReporter(makeAddr("candidate"));
    }
}
