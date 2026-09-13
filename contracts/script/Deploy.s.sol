// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {JobEscrow} from "../src/JobEscrow.sol";
import {SourceRegistry} from "../src/SourceRegistry.sol";
import {TestUSDC} from "../src/TestUSDC.sol";
import {WorkOracle} from "../src/WorkOracle.sol";

/// @notice Deploys the source-chain half onto Ethereum Sepolia.
/// @dev forge script script/Deploy.s.sol:DeploySource --rpc-url $SOURCE_CHAIN_RPC_URL --broadcast
contract DeploySource is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("CREDITCOIN_WALLET_PRIVATE_KEY"));
        WorkOracle oracle = new WorkOracle();
        vm.stopBroadcast();

        console.log("WORK_ORACLE_ADDRESS=%s", address(oracle));
        console.log("chainid=%s", block.chainid);
    }
}

/// @notice Deploys the settlement half onto Creditcoin CC3 Testnet and wires the registry.
/// @dev forge script script/Deploy.s.sol:DeployCreditcoin --rpc-url $CREDITCOIN_RPC_URL --broadcast
///      Requires WORK_ORACLE_ADDRESS from the Sepolia deployment above.
contract DeployCreditcoin is Script {
    /// @dev Builder bond, 20% of the job amount.
    uint16 internal constant BOND_BPS = 2_000;
    /// @dev Challenger's cut of that bond, 50%.
    uint16 internal constant BOUNTY_BPS = 5_000;

    function run() external {
        address workOracle = vm.envAddress("WORK_ORACLE_ADDRESS");
        uint64 sourceChainKey = uint64(vm.envOr("SOURCE_CHAIN_KEY", uint256(1)));
        uint64 sourceEvmChainId = uint64(vm.envOr("SOURCE_EVM_CHAIN_ID", uint256(11_155_111)));

        vm.startBroadcast(vm.envUint("CREDITCOIN_WALLET_PRIVATE_KEY"));

        TestUSDC usdc = new TestUSDC();
        SourceRegistry registry = new SourceRegistry();
        JobEscrow escrow = new JobEscrow(usdc, registry, BOND_BPS, BOUNTY_BPS);

        registry.registerSource(
            workOracle,
            SourceRegistry.Source({
                registered: false, // the registry sets this
                chainKey: sourceChainKey,
                evmChainId: sourceEvmChainId,
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

        vm.stopBroadcast();

        console.log("TEST_USDC_ADDRESS=%s", address(usdc));
        console.log("SOURCE_REGISTRY_ADDRESS=%s", address(registry));
        console.log("JOB_ESCROW_ADDRESS=%s", address(escrow));
        console.log("registered source=%s chainKey=%s", workOracle, sourceChainKey);
    }
}
