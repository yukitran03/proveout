// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestUSDC
 * @notice Six-decimal demo stand-in for USDC with an open mint.
 * @dev NOT USDC. Anyone may mint any amount. It exists so the CC3 Testnet demo
 *      has a settlement asset; it carries no value and must never be treated as one.
 */
contract TestUSDC is ERC20 {
    constructor() ERC20("ProveOut Test USDC", "tUSDC") {}

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint demo tokens to any address. Open on purpose; testnet only.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount in micro-units (1 tUSDC = 1e6).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
