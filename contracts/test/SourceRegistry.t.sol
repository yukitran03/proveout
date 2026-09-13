// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {SourceRegistry} from "../src/SourceRegistry.sol";

/// @notice The registry decides which source-chain emitter counts, so its validation is
///         load-bearing: a wrong field position does not revert, it returns plausible
///         garbage, and a wrong emitter drains every escrow that trusts it.
contract SourceRegistryTest is Test {
    SourceRegistry internal registry;

    address internal owner = address(this);
    address internal stranger = makeAddr("stranger");
    address internal emitter = makeAddr("emitter");

    bytes32 internal constant TOPIC_COMPLETED = keccak256("WorkCompleted(bytes32,bytes32,address,bytes32)");
    bytes32 internal constant TOPIC_FAILED = keccak256("WorkFailed(bytes32,bytes32)");

    event SourceRegistered(address indexed emitter, uint64 indexed chainKey, uint64 evmChainId);
    event SourceRemoved(address indexed emitter);

    function setUp() public {
        registry = new SourceRegistry();
    }

    function _valid() internal pure returns (SourceRegistry.Source memory) {
        return SourceRegistry.Source({
            registered: false,
            chainKey: 1,
            evmChainId: 11_155_111,
            topic0Completed: TOPIC_COMPLETED,
            topic0Failed: TOPIC_FAILED,
            completedJobIdTopic: 1,
            completedCriteriaTopic: 2,
            completedBuilderTopic: 3,
            failedJobIdTopic: 1,
            completedTopicCount: 4,
            failedTopicCount: 3
        });
    }

    // ------------------------------------------------------------ happy path

    function test_registerSource_storesTheLayoutAndMarksItRegistered() public {
        registry.registerSource(emitter, _valid());
        SourceRegistry.Source memory s = registry.getSource(emitter);

        assertTrue(s.registered);
        assertEq(s.chainKey, 1);
        assertEq(s.evmChainId, 11_155_111);
        assertEq(s.topic0Completed, TOPIC_COMPLETED);
        assertEq(s.topic0Failed, TOPIC_FAILED);
        assertEq(s.completedJobIdTopic, 1);
        assertEq(s.completedCriteriaTopic, 2);
        assertEq(s.completedBuilderTopic, 3);
        assertEq(s.failedJobIdTopic, 1);
        assertEq(s.completedTopicCount, 4);
        assertEq(s.failedTopicCount, 3);
    }

    function test_registerSource_ignoresTheCallersRegisteredFlag() public {
        SourceRegistry.Source memory s = _valid();
        s.registered = false;
        registry.registerSource(emitter, s);
        assertTrue(registry.isRegistered(emitter));
    }

    function test_registerSource_emitsSourceRegistered() public {
        vm.expectEmit(true, true, false, true);
        emit SourceRegistered(emitter, 1, 11_155_111);
        registry.registerSource(emitter, _valid());
    }

    function test_unregisteredEmitter_readsAsNotRegistered() public view {
        assertFalse(registry.isRegistered(emitter));
        assertFalse(registry.getSource(emitter).registered);
    }

    function test_requireSource_revertsForAnUnknownEmitter() public {
        vm.expectRevert(abi.encodeWithSelector(SourceRegistry.NotRegistered.selector, emitter));
        registry.requireSource(emitter);
    }

    function test_requireSource_returnsTheSourceWhenKnown() public {
        registry.registerSource(emitter, _valid());
        assertEq(registry.requireSource(emitter).evmChainId, 11_155_111);
    }

    // ------------------------------------------------------------ access

    function test_registerSource_isRefused_whenCallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(SourceRegistry.NotOwner.selector);
        registry.registerSource(emitter, _valid());
    }

    function test_removeSource_isRefused_whenCallerIsNotOwner() public {
        registry.registerSource(emitter, _valid());
        vm.prank(stranger);
        vm.expectRevert(SourceRegistry.NotOwner.selector);
        registry.removeSource(emitter);
    }

    function test_transferOwnership_movesControl() public {
        registry.transferOwnership(stranger);
        assertEq(registry.owner(), stranger);
        vm.prank(stranger);
        registry.registerSource(emitter, _valid());
        assertTrue(registry.isRegistered(emitter));
    }

    function test_transferOwnership_isRefused_forTheZeroAddress() public {
        vm.expectRevert(SourceRegistry.ZeroAddress.selector);
        registry.transferOwnership(address(0));
    }

    // ------------------------------------------------------------ removal

    function test_removeSource_clearsTheEntry() public {
        registry.registerSource(emitter, _valid());
        registry.removeSource(emitter);
        assertFalse(registry.isRegistered(emitter));
    }

    function test_removeSource_emitsSourceRemoved() public {
        registry.registerSource(emitter, _valid());
        vm.expectEmit(true, false, false, true);
        emit SourceRemoved(emitter);
        registry.removeSource(emitter);
    }

    function test_removeSource_isRefused_whenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(SourceRegistry.NotRegistered.selector, emitter));
        registry.removeSource(emitter);
    }

    /// @dev Re-registration must go through removal. A silent redefinition would change how
    ///      jobs that are already funded settle, after their money was committed.
    function test_registerSource_isRefused_whenAlreadyRegistered() public {
        registry.registerSource(emitter, _valid());
        vm.expectRevert(abi.encodeWithSelector(SourceRegistry.AlreadyRegistered.selector, emitter));
        registry.registerSource(emitter, _valid());
    }

    function test_removeThenRegister_allowsADeliberateRedefinition() public {
        registry.registerSource(emitter, _valid());
        registry.removeSource(emitter);

        SourceRegistry.Source memory s = _valid();
        s.evmChainId = 1;
        registry.registerSource(emitter, s);
        assertEq(registry.getSource(emitter).evmChainId, 1);
    }

    // ------------------------------------------------------------ validation

    function test_registerSource_isRefused_forTheZeroAddress() public {
        vm.expectRevert(SourceRegistry.ZeroAddress.selector);
        registry.registerSource(address(0), _valid());
    }

    function test_registerSource_isRefused_whenACompletionTopicIsEmpty() public {
        SourceRegistry.Source memory s = _valid();
        s.topic0Completed = bytes32(0);
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    function test_registerSource_isRefused_whenAFailureTopicIsEmpty() public {
        SourceRegistry.Source memory s = _valid();
        s.topic0Failed = bytes32(0);
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    /// @dev Identical signatures would make a failure settle as a completion.
    function test_registerSource_isRefused_whenBothTopicsAreTheSame() public {
        SourceRegistry.Source memory s = _valid();
        s.topic0Failed = s.topic0Completed;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    /// @dev Topic 0 is always the event signature, so no field may claim it.
    function test_registerSource_isRefused_whenAFieldClaimsTopicZero() public {
        SourceRegistry.Source memory s = _valid();
        s.completedJobIdTopic = 0;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    /// @dev A log carries at most four topics.
    function test_registerSource_isRefused_whenAFieldIsBeyondTopicThree() public {
        SourceRegistry.Source memory s = _valid();
        s.completedBuilderTopic = 4;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    function test_registerSource_isRefused_whenTopicCountIsZero() public {
        SourceRegistry.Source memory s = _valid();
        s.completedTopicCount = 0;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    function test_registerSource_isRefused_whenTopicCountExceedsFour() public {
        SourceRegistry.Source memory s = _valid();
        s.completedTopicCount = 5;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    /// @dev A field index at or past the declared count would read outside the log.
    function test_registerSource_isRefused_whenAFieldSitsOutsideTheDeclaredCount() public {
        SourceRegistry.Source memory s = _valid();
        s.completedTopicCount = 3; // but builder is declared at index 3
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    function test_registerSource_isRefused_whenFailureFieldSitsOutsideItsCount() public {
        SourceRegistry.Source memory s = _valid();
        s.failedJobIdTopic = 3;
        s.failedTopicCount = 3;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    function test_registerSource_isRefused_whenFailedTopicCountIsZero() public {
        SourceRegistry.Source memory s = _valid();
        s.failedTopicCount = 0;
        vm.expectRevert(SourceRegistry.InvalidTopicLayout.selector);
        registry.registerSource(emitter, s);
    }

    // ------------------------------------------------------- many sources

    /// @dev Sources are configuration, not code. Adding a chain is one transaction.
    function test_manySources_coexistWithIndependentLayouts() public {
        address second = makeAddr("mainnetEmitter");
        registry.registerSource(emitter, _valid());

        SourceRegistry.Source memory s = _valid();
        s.chainKey = 3;
        s.evmChainId = 1;
        s.completedCriteriaTopic = 3;
        s.completedBuilderTopic = 2;
        registry.registerSource(second, s);

        assertEq(registry.getSource(emitter).chainKey, 1);
        assertEq(registry.getSource(second).chainKey, 3);
        assertEq(registry.getSource(second).completedBuilderTopic, 2);
    }

    function testFuzz_onlyOwnerCanRegister(address caller) public {
        vm.assume(caller != owner);
        vm.prank(caller);
        vm.expectRevert(SourceRegistry.NotOwner.selector);
        registry.registerSource(emitter, _valid());
    }
}
