// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Market Position Interface
/// @notice Interface for managing collateralized debt positions in markets
/// @dev Handles deposits, withdrawals, minting, burning, liquidations and redemptions
interface IMarketPosition {
    /// @notice Emitted when collateral is deposited into a market
    /// @param debtToken Address of the debt token
    /// @param depositor Address that initiated the deposit
    /// @param to Address that received the deposit credit
    /// @param amount Amount of collateral deposited
    event Deposit(address indexed debtToken, address indexed depositor, address indexed to, uint128 amount);

    /// @notice Emitted when collateral is withdrawn from a market
    /// @param debtToken Address of the debt token
    /// @param withdrawer Address that initiated the withdrawal
    /// @param to Address that received the withdrawn collateral
    /// @param amount Amount of collateral withdrawn
    event Withdraw(address indexed debtToken, address indexed withdrawer, address indexed to, uint128 amount);

    /// @notice Emitted when debt tokens are minted
    /// @param debtToken Address of the debt token
    /// @param minter Address that initiated the mint
    /// @param to Address that received the minted tokens
    /// @param amount Amount of debt tokens minted
    /// @param relativePrice Price ratio between collateral and debt where collateralAmount = debtAmount * relativePrice
    event Mint(
        address indexed debtToken, address indexed minter, address indexed to, uint128 amount, uint256 relativePrice
    );

    /// @notice Emitted when debt tokens are burned
    /// @param debtToken Address of the debt token
    /// @param burner Address that initiated the burn
    /// @param to Address that received credit for the burn
    /// @param amount Amount of debt tokens burned
    event Burn(address indexed debtToken, address indexed burner, address indexed to, uint128 amount);

    /// @notice Emitted when a position is liquidated
    /// @param debtToken Address of the debt token
    /// @param liquidator Address that performed the liquidation
    /// @param user Address of the position owner that was liquidated
    /// @param debtCovered Amount of debt that was covered by the liquidation
    /// @param collateralLiquidated Amount of collateral that was liquidated
    /// @param relativePrice Price ratio between collateral and debt where collateralAmount = debtAmount * relativePrice
    event Liquidate(
        address indexed debtToken,
        address indexed liquidator,
        address indexed user,
        uint128 debtCovered,
        uint128 collateralLiquidated,
        uint256 relativePrice
    );

    /// @notice Emitted when debt tokens are redeemed for collateral
    /// @param debtToken Address of the debt token
    /// @param redeemer Address that initiated the redemption
    /// @param to Address that received the collateral
    /// @param amount Amount of debt tokens redeemed
    /// @param collateralReceived Amount of collateral received in exchange
    event Redeem(
        address indexed debtToken,
        address indexed redeemer,
        address indexed to,
        uint128 amount,
        uint128 collateralReceived
    );

    /// @notice Emitted when a position is closed
    /// @param debtToken Address of the debt token
    /// @param closer Address that closed the position
    /// @param to Address that received the collateral
    /// @param amount Amount of collateral withdrawn when closing the position
    event Close(address indexed debtToken, address indexed closer, address indexed to, uint128 amount);

    /// @notice Deposits collateral into a market
    /// @param debtToken Address of the debt token
    /// @param to Address to credit the deposit to
    /// @param amount Amount of collateral to deposit
    function deposit(address debtToken, address to, uint128 amount) external payable;

    /// @notice Withdraws collateral from a market
    /// @param debtToken Address of the debt token
    /// @param to Address to receive the withdrawn collateral
    /// @param amount Amount of collateral to withdraw
    function withdraw(address debtToken, address to, uint128 amount) external payable;

    /// @notice Mints debt tokens against deposited collateral
    /// @param debtToken Address of the debt token
    /// @param to Address to receive the minted debt tokens
    /// @param amount Amount of debt tokens to mint
    function mint(address debtToken, address to, uint128 amount) external payable;

    /// @notice Burns debt tokens to reduce debt
    /// @param debtToken Address of the debt token
    /// @param to Address to credit the debt reduction to
    /// @param amount Amount of debt tokens to burn
    function burn(address debtToken, address to, uint128 amount) external payable;

    /// @notice Liquidates an undercollateralized position
    /// @param debtToken Address of the debt token
    /// @param user Address of the position owner to liquidate
    /// @param debtToCover Amount of debt to cover in the liquidation
    /// @param skipCallback Whether to skip the callback to the liquidator
    /// @param data Additional data for the liquidation
    /// @return debtCovered The actual amount of debt that was covered
    /// @return collateralLiquidated The amount of collateral that was liquidated
    function liquidate(address debtToken, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        payable
        returns (uint128 debtCovered, uint128 collateralLiquidated);

    /// @notice Redeems debt tokens for collateral
    /// @param debtToken Address of the debt token
    /// @param to Address to receive the collateral
    /// @param amount Amount of debt tokens to redeem
    /// @return collateralReceived The amount of collateral received in exchange
    function redeem(address debtToken, address to, uint128 amount)
        external
        payable
        returns (uint128 collateralReceived);

    /// @notice Closes a position and withdraws remaining collateral
    /// @param debtToken Address of the debt token
    /// @param to Address to receive the withdrawn collateral
    /// @return collateralReceived The amount of collateral received
    function close(address debtToken, address to) external payable returns (uint128 collateralReceived);
}
