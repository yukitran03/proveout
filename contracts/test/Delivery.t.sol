// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Base} from "./Base.t.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {SourceRegistry} from "../src/SourceRegistry.sol";
import {ProvedTx} from "./harness/ProvedTx.sol";

/// @notice Jobs whose acceptance criterion is an on-chain delivery by an ordinary token.
/// @dev The point of this path is that nothing in it trusts a reporter. The token has never
///      heard of ProveOut, cannot be configured by anyone here, and emits `Transfer` only
///      when tokens actually move. Where the attested path narrows source-side trust to one
///      named contract, this path removes it.
contract DeliveryTest is Base {
    bytes32 internal constant TOPIC_TRANSFER = keccak256("Transfer(address,address,uint256)");

    /// @dev Stands in for a real third-party ERC-20 on the source chain.
    address internal srcToken = makeAddr("sourceToken");
    address internal beneficiary = makeAddr("beneficiary");

    bytes32 internal constant DJOB = keccak256("delivery-job-1");
    uint256 internal constant MIN_DELIVERY = 5 ether;

    function setUp() public override {
        super.setUp();
        registry.registerSource(srcToken, _deliverySource());
    }

    function _deliverySource() internal pure returns (SourceRegistry.Source memory) {
        return SourceRegistry.Source({
            registered: false,
            kind: SourceRegistry.Kind.Delivery,
            chainKey: SEPOLIA_CHAIN_KEY,
            evmChainId: SEPOLIA_CHAIN_ID,
            topic0Completed: TOPIC_TRANSFER,
            topic0Failed: bytes32(0),
            completedJobIdTopic: 0,
            completedCriteriaTopic: 0,
            completedBuilderTopic: 0,
            failedJobIdTopic: 0,
            completedTopicCount: 3,
            failedTopicCount: 0,
            deliveryFromTopic: 1,
            deliveryToTopic: 2
        });
    }

    function _transferLog(address emitter, address from, address to, uint256 value)
        internal
        pure
        returns (ProvedTx.Log memory)
    {
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = TOPIC_TRANSFER;
        topics[1] = bytes32(uint256(uint160(from)));
        topics[2] = bytes32(uint256(uint160(to)));
        return ProvedTx.Log({emitter: emitter, topics: topics, data: abi.encode(value)});
    }

    function _openDeliveryJob() internal {
        vm.prank(buyer);
        escrow.createDeliveryJob(DJOB, builder, AMOUNT, deadline, CRITERIA, srcToken, beneficiary, MIN_DELIVERY);
        vm.prank(builder);
        escrow.postBond(DJOB);
        vm.prank(buyer);
        escrow.fundJob(DJOB);
    }

    function _deliveryTx(address from, address to, uint256 value) internal view returns (bytes memory) {
        return ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_transferLog(srcToken, from, to, value)));
    }

    // ------------------------------------------------------------ happy path

    function test_delivery_releases_whenTheTokenItselfSaysTheTransferHappened() public {
        _openDeliveryJob();
        uint256 before = token_balanceOfBuilder();

        _release(stranger, _deliveryTx(builder, beneficiary, MIN_DELIVERY), 1);

        assertEq(token_balanceOfBuilder() - before, uint256(AMOUNT) + BOND);
        assertEq(uint8(escrow.getJob(DJOB).status), uint8(JobEscrow.Status.Released));
    }

    function test_delivery_acceptsMoreThanTheMinimum() public {
        _openDeliveryJob();
        _release(stranger, _deliveryTx(builder, beneficiary, MIN_DELIVERY * 3), 1);
        assertEq(uint8(escrow.getJob(DJOB).status), uint8(JobEscrow.Status.Released));
    }

    /// @dev No reporter, no oracle, no privileged caller anywhere in this path.
    function test_delivery_needsNoReporterAndNoOracle() public {
        _openDeliveryJob();
        // sourceOracle is not involved at all; the token is the only registered emitter here.
        assertEq(escrow.getJob(DJOB).source, srcToken);
        _release(challenger, _deliveryTx(builder, beneficiary, MIN_DELIVERY), 1);
        assertEq(uint8(escrow.getJob(DJOB).status), uint8(JobEscrow.Status.Released));
    }

    // ------------------------------------------------------------- refusals

    function test_delivery_isRefused_whenTheAmountIsBelowTheMinimum() public {
        _openDeliveryJob();
        vm.expectRevert(
            abi.encodeWithSelector(JobEscrow.DeliveryTooSmall.selector, DJOB, MIN_DELIVERY, MIN_DELIVERY - 1)
        );
        _release(stranger, _deliveryTx(builder, beneficiary, MIN_DELIVERY - 1), 1);
    }

    function test_delivery_isRefused_whenSomeoneElseSentTheTokens() public {
        _openDeliveryJob();
        // A different sender is a different route, so it matches no job at all.
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, _deliveryTx(stranger, beneficiary, MIN_DELIVERY), 1);
    }

    function test_delivery_isRefused_whenTheTokensWentToTheWrongAddress() public {
        _openDeliveryJob();
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, _deliveryTx(builder, stranger, MIN_DELIVERY), 1);
    }

    function test_delivery_isRefused_whenTheTokenIsNotRegistered() public {
        _openDeliveryJob();
        address otherToken = makeAddr("otherToken");
        bytes memory tx_ = ProvedTx.type2(
            SEPOLIA_CHAIN_ID, 1, ProvedTx.one(_transferLog(otherToken, builder, beneficiary, MIN_DELIVERY))
        );
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, tx_, 1);
    }

    function test_delivery_isRefused_whenTheReceiptFailed() public {
        _openDeliveryJob();
        bytes memory reverted =
            ProvedTx.type2(SEPOLIA_CHAIN_ID, 0, ProvedTx.one(_transferLog(srcToken, builder, beneficiary, MIN_DELIVERY)));
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.ReceiptNotSuccessful.selector, uint8(0)));
        _release(stranger, reverted, 1);
    }

    function test_delivery_isRefused_afterTheDeadline() public {
        _openDeliveryJob();
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.DeadlinePassed.selector, DJOB, deadline));
        _release(stranger, _deliveryTx(builder, beneficiary, MIN_DELIVERY), 1);
    }

    function test_delivery_isRefused_whenProvedOnTheWrongChain() public {
        _openDeliveryJob();
        bytes memory wrongChain =
            ProvedTx.type2(MAINNET_CHAIN_ID, 1, ProvedTx.one(_transferLog(srcToken, builder, beneficiary, MIN_DELIVERY)));
        vm.expectRevert(
            abi.encodeWithSelector(JobEscrow.SourceChainMismatch.selector, SEPOLIA_CHAIN_ID, MAINNET_CHAIN_ID)
        );
        _release(stranger, wrongChain, 1);
    }

    /// @dev A delivery source has no failure event, so there is nothing to challenge with.
    function test_delivery_cannotBeChallenged() public {
        _openDeliveryJob();
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _challenge(challenger, _deliveryTx(builder, beneficiary, MIN_DELIVERY), 1);
    }

    function test_delivery_stillFallsBackToRefundAfterTheDeadline() public {
        _openDeliveryJob();
        uint256 before = token_balanceOfBuyer();
        vm.warp(deadline + 1);
        escrow.refund(DJOB);
        assertEq(token_balanceOfBuyer() - before, uint256(AMOUNT) + BOND);
    }

    // ----------------------------------------------------------- other logs

    /// @dev An ordinary token emits transfers all day that have nothing to do with us. They
    ///      must be skipped quietly, not revert somebody else's settlement.
    function test_unrelatedTransfersInTheSameTransaction_areIgnored() public {
        _openDeliveryJob();
        ProvedTx.Log[] memory logs = new ProvedTx.Log[](3);
        logs[0] = _transferLog(srcToken, stranger, challenger, 99 ether);
        logs[1] = _transferLog(srcToken, builder, beneficiary, MIN_DELIVERY);
        logs[2] = _transferLog(srcToken, challenger, stranger, 1 ether);

        _release(stranger, ProvedTx.type2(SEPOLIA_CHAIN_ID, 1, logs), 1);
        assertEq(uint8(escrow.getJob(DJOB).status), uint8(JobEscrow.Status.Released));
    }

    function test_aTransactionOfOnlyUnrelatedTransfers_settlesNothing() public {
        _openDeliveryJob();
        vm.expectRevert(JobEscrow.NoMatchingLogs.selector);
        _release(stranger, _deliveryTx(stranger, challenger, 1 ether), 1);
    }

    // ------------------------------------------------------------ the route

    function test_route_isReservedAtCreation() public {
        _openDeliveryJob();
        assertEq(escrow.deliveryRoute(escrow.deliveryKey(srcToken, builder, beneficiary)), DJOB);
    }

    /// @dev Two live jobs on the same route would make one proved Transfer ambiguous.
    function test_route_cannotBeTakenTwice() public {
        _openDeliveryJob();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(JobEscrow.DeliveryRouteTaken.selector, DJOB));
        escrow.createDeliveryJob(
            keccak256("delivery-job-2"), builder, AMOUNT, deadline, CRITERIA, srcToken, beneficiary, MIN_DELIVERY
        );
    }

    function test_route_differsByRecipient() public {
        _openDeliveryJob();
        address other = makeAddr("otherBeneficiary");
        vm.prank(buyer);
        escrow.createDeliveryJob(
            keccak256("delivery-job-2"), builder, AMOUNT, deadline, CRITERIA, srcToken, other, MIN_DELIVERY
        );
        assertTrue(
            escrow.deliveryRoute(escrow.deliveryKey(srcToken, builder, other))
                != escrow.deliveryRoute(escrow.deliveryKey(srcToken, builder, beneficiary))
        );
    }

    // ------------------------------------------------------- kind mismatches

    function test_createDeliveryJob_isRefused_forAnAttestingSource() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongSourceKind.selector, SourceRegistry.Kind.Delivery, SourceRegistry.Kind.Attested
            )
        );
        escrow.createDeliveryJob(
            DJOB, builder, AMOUNT, deadline, CRITERIA, sourceOracle, beneficiary, MIN_DELIVERY
        );
    }

    function test_createJob_isRefused_forADeliverySource() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                JobEscrow.WrongSourceKind.selector, SourceRegistry.Kind.Attested, SourceRegistry.Kind.Delivery
            )
        );
        escrow.createJob(DJOB, builder, AMOUNT, deadline, CRITERIA, srcToken);
    }

    function test_createDeliveryJob_isRefused_withoutABeneficiary() public {
        vm.prank(buyer);
        vm.expectRevert(JobEscrow.ZeroAddress.selector);
        escrow.createDeliveryJob(DJOB, builder, AMOUNT, deadline, CRITERIA, srcToken, address(0), MIN_DELIVERY);
    }

    function test_createDeliveryJob_isRefused_withoutAMinimum() public {
        vm.prank(buyer);
        vm.expectRevert(JobEscrow.ZeroAmount.selector);
        escrow.createDeliveryJob(DJOB, builder, AMOUNT, deadline, CRITERIA, srcToken, beneficiary, 0);
    }

    // ---------------------------------------------------------------- utils

    function token_balanceOfBuilder() internal view returns (uint256) {
        return token_balanceOf(builder);
    }

    function token_balanceOfBuyer() internal view returns (uint256) {
        return token_balanceOf(buyer);
    }

    function token_balanceOf(address who) internal view returns (uint256) {
        return token.balanceOf(who);
    }
}
