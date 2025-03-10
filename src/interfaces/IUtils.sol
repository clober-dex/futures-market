// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IUtils {
    /// @notice Allows a user to approve a spender to spend their tokens
    /// @param token Address of the token to approve
    /// @param value Amount of tokens to approve
    /// @param deadline Timestamp after which the approval is no longer valid
    /// @param v ECDSA signature component
    /// @param r ECDSA signature component
    /// @param s ECDSA signature component
    function permit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external payable;

    /// @notice Allows a user to call multiple functions in a single transaction
    /// @param data Array of calldata for each function to call
    /// @return results Array of return values from each function call
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}
