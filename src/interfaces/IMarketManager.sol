// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Market Manager Interface
/// @notice Interface for managing debt markets with collateral
interface IMarketManager {
    /// @notice Emitted when a new market is opened
    /// @param debtToken Address of the debt token created for this market
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the market expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision (e.g. 50% = 500000)
    /// @param liquidationThreshold Threshold at which positions can be liquidated as a percentage with 1e6 precision
    /// @param minDebt Minimum debt amount that must be minted
    event Open(
        address indexed debtToken,
        bytes32 assetId,
        address collateral,
        uint40 expiration,
        uint24 ltv,
        uint24 liquidationThreshold,
        uint128 minDebt
    );

    /// @notice Emitted when market expiration time is updated
    /// @param debtToken Address of the debt token
    /// @param expiration New expiration timestamp
    event ChangeExpiration(address indexed debtToken, uint40 expiration);

    /// @notice Emitted when market LTV ratio is updated
    /// @param debtToken Address of the debt token
    /// @param ltv New Loan-to-Value ratio as a percentage with 1e6 precision
    event ChangeLtv(address indexed debtToken, uint24 ltv);

    /// @notice Emitted when market liquidation threshold is updated
    /// @param debtToken Address of the debt token
    /// @param liquidationThreshold New liquidation threshold as a percentage with 1e6 precision
    event ChangeLiquidationThreshold(address indexed debtToken, uint24 liquidationThreshold);

    /// @notice Emitted when market minimum debt amount is updated
    /// @param debtToken Address of the debt token
    /// @param minDebt New minimum debt amount that must be minted
    event ChangeMinDebt(address indexed debtToken, uint128 minDebt);

    /// @notice Emitted when a market is settled at expiration
    /// @param debtToken Address of the debt token
    /// @param settlePrice The final settlement price used for the market
    event Settle(address indexed debtToken, uint256 settlePrice);

    /// @notice Creates a new market with the specified configuration
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the market expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision (e.g. 50% = 500000)
    /// @param liquidationThreshold Threshold at which positions can be liquidated as a percentage with 1e6 precision
    /// @param minDebt Minimum debt amount that must be minted
    /// @param name Name of the debt token
    /// @param symbol Symbol of the debt token
    /// @return debtToken Address of the created debt token
    function open(
        bytes32 assetId,
        address collateral,
        uint40 expiration,
        uint24 ltv,
        uint24 liquidationThreshold,
        uint128 minDebt,
        string calldata name,
        string calldata symbol
    ) external payable returns (address debtToken);

    /// @notice Updates the market expiration time
    /// @param debtToken Address of the debt token
    /// @param expiration New expiration timestamp
    function changeExpiration(address debtToken, uint40 expiration) external;

    /// @notice Updates the market LTV ratio
    /// @param debtToken Address of the debt token
    /// @param ltv New Loan-to-Value ratio as a percentage with 1e6 precision
    function changeLtv(address debtToken, uint24 ltv) external;

    /// @notice Updates the market liquidation threshold
    /// @param debtToken Address of the debt token
    /// @param liquidationThreshold New liquidation threshold as a percentage with 1e6 precision
    function changeLiquidationThreshold(address debtToken, uint24 liquidationThreshold) external;

    /// @notice Updates the market minimum debt amount
    /// @param debtToken Address of the debt token
    /// @param minDebt New minimum debt amount that must be minted
    function changeMinDebt(address debtToken, uint128 minDebt) external;

    /// @notice Settles a market after expiration
    /// @param debtToken Address of the debt token
    /// @return settlePrice The final settlement price used for the market
    function settle(address debtToken) external payable returns (uint256 settlePrice);

    /// @notice Updates the oracle with new price data
    /// @param data Encoded oracle update data
    function updateOracle(bytes calldata data) external payable;
}
