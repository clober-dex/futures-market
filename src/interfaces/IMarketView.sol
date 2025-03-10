// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Market View Interface
/// @notice Interface for viewing market and position data
interface IMarketView {
    /// @notice Market configuration and state data
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the market expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision (e.g. 50% = 500000)
    /// @param liquidationThreshold Threshold at which positions can be liquidated as a percentage with 1e6 precision
    /// @param minDebt Minimum debt amount that must be minted
    /// @param settlePrice Settlement price for the underlying asset, set when market is settled
    struct Market {
        bytes32 assetId;
        address collateral;
        uint40 expiration;
        uint24 ltv;
        uint24 liquidationThreshold;
        uint128 minDebt;
        uint256 settlePrice;
    }

    /// @notice Gets the market configuration and state data
    /// @param debtToken Address of the debt token
    /// @return market Market data struct containing configuration and state
    function getMarket(address debtToken) external view returns (Market memory market);

    /// @notice Gets a user's position in a market
    /// @param debtToken Address of the debt token
    /// @param user Address of the position owner
    /// @return collateral Amount of collateral deposited
    /// @return debt Amount of debt minted
    function getPosition(address debtToken, address user) external view returns (uint128 collateral, uint128 debt);

    /// @notice Checks if a market has been settled
    /// @param debtToken Address of the debt token
    /// @return settled True if market is settled, false otherwise
    function isSettled(address debtToken) external view returns (bool settled);
}
