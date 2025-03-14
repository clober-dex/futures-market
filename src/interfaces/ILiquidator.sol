// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Liquidator Interface for Vault Position Liquidations
/// @notice Interface for handling callbacks when vault positions are liquidated
/// @dev Implements callback functionality to process liquidation events from the VaultManager
interface ILiquidator {
    /// @notice Callback function called by VaultManager when a position is liquidated
    /// @param debtToken Address of the debt token
    /// @param user Address of the position owner that was liquidated
    /// @param debtCovered Amount of debt that was covered by the liquidation
    /// @param collateralLiquidated Amount of collateral that was seized during liquidation
    /// @param relativePrice Price ratio between collateral and debt where collateralAmount = debtAmount * relativePrice
    /// @param data Additional data for the liquidation
    function onLiquidation(
        address debtToken,
        address user,
        uint128 debtCovered,
        uint128 collateralLiquidated,
        uint256 relativePrice,
        bytes calldata data
    ) external;
}
