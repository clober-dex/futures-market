// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Vault Manager Interface for Collateralized Debt Positions
/// @notice Interface for managing vaults that allow users to deposit collateral and mint debt tokens
/// @dev Handles vault creation, collateral management, debt minting/burning, liquidations, and settlement
interface IVaultManager {
    error InvalidConfig();
    error VaultAlreadyExists();
    error VaultDoesNotExist();
    error InsufficientCollateral();
    error LTVExceeded();
    error PositionSafe();
    error BurnExceedsDebt();
    error NotExpired();
    error AlreadySettled();
    error NotSettled();
    error InvalidFlashLoanCallback();

    /// @notice Configuration parameters for a vault
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the vault expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision (e.g. 50% = 500000)
    /// @param liquidationThreshold Threshold at which positions can be liquidated as a percentage with 1e6 precision (e.g. 75% = 750000)
    /// @param minDebt Minimum debt amount that must be minted
    /// @param settlePrice Settlement price for the underlying asset, set when vault is settled
    struct Config {
        bytes32 assetId;
        address collateral;
        uint40 expiration;
        uint24 ltv;
        uint24 liquidationThreshold;
        uint128 minDebt;
        uint256 settlePrice;
    }

    /// @notice Position details for a user in a vault
    /// @param collateral Amount of collateral deposited
    /// @param debt Amount of debt minted
    struct Position {
        uint128 collateral;
        uint128 debt;
    }

    /// @notice Emitted when a new vault is created
    /// @param debtToken Address of the debt token created for this vault
    /// @param debtToken Address of the debt token created for this vault
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the vault expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision
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

    /// @notice Emitted when collateral is deposited into a vault
    /// @param debtToken Address of the debt token
    /// @param depositor Address that initiated the deposit
    /// @param to Address that received the deposit credit
    /// @param amount Amount of collateral deposited
    event Deposit(address indexed debtToken, address indexed depositor, address indexed to, uint128 amount);

    /// @notice Emitted when collateral is withdrawn from a vault
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

    /// @notice Emitted when a vault is settled at expiration
    /// @param debtToken Address of the debt token
    /// @param settlePrice The final settlement relative price used for the vault
    event Settle(address indexed debtToken, uint256 settlePrice);

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

    /// @notice Emitted when debt tokens are redeemed for collateral after settlement
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

    /// @notice Emitted when a vault is closed
    /// @param debtToken Address of the debt token
    /// @param closer Address that closed the vault
    /// @param to Address that received the collateral
    /// @param amount Amount of collateral withdrawn when closing the vault
    event Close(address indexed debtToken, address indexed closer, address indexed to, uint128 amount);

    /// @notice Returns the address of the price oracle used by the vault manager
    /// @return oracle Address of the price oracle contract
    function priceOracle() external view returns (address oracle);

    /// @notice Retrieves the configuration for a specific vault
    /// @param debtToken Address of the debt token
    /// @return config Config struct containing vault parameters
    function getConfig(address debtToken) external view returns (Config memory config);

    /// @notice Retrieves the position details for a specific user in a vault
    /// @param debtToken Address of the debt token
    /// @param user Address of the position owner
    /// @return position Position struct containing collateral and debt amounts
    function getPosition(address debtToken, address user) external view returns (Position memory position);

    /// @notice Checks if a vault has been settled
    /// @param debtToken Address of the debt token
    /// @return settled True if the vault has been settled, false otherwise
    function isSettled(address debtToken) external view returns (bool settled);

    /// @notice Creates a new vault with the specified configuration
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the vault expires
    /// @param ltv Loan-to-Value ratio as a percentage with 1e6 precision (e.g. 50% = 500000)
    /// @param liquidationThreshold Threshold at which positions can be liquidated as a percentage with 1e6 precision (e.g. 75% = 750000)
    /// @param minDebt Minimum debt amount that must be minted
    /// @param name Name of the debt token
    /// @param symbol Symbol of the debt token
    /// @return debtToken Address of the debt token
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

    /// @notice Deposits collateral into a vault
    /// @param debtToken Address of the debt token
    /// @param to Address to credit the deposit to
    /// @param amount Amount of collateral to deposit
    function deposit(address debtToken, address to, uint128 amount) external payable;

    /// @notice Withdraws collateral from a vault
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

    /// @notice Settles a vault after expiration
    /// @param debtToken Address of the debt token
    /// @return settlePrice The final settlement price used for the vault
    function settle(address debtToken) external payable returns (uint256 settlePrice);

    /// @notice Liquidates an undercollateralized position
    /// @param debtToken Address of the debt token
    /// @param user Address of the position owner to liquidate
    /// @param debtToCover Amount of debt to cover in the liquidation
    /// @param skipCallback Whether to skip the callback to the liquidator
    /// @param data Additional data for the liquidation
    /// @return debtCovered The actual amount of debt that was covered in the liquidation
    /// @return collateralLiquidated The amount of collateral that was liquidated
    function liquidate(address debtToken, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        payable
        returns (uint128 debtCovered, uint128 collateralLiquidated);

    /// @notice Redeems debt tokens for collateral after settlement
    /// @param debtToken Address of the debt token
    /// @param to Address to receive the collateral
    /// @param amount Amount of debt tokens to redeem
    /// @return collateralReceived The amount of collateral received in exchange
    function redeem(address debtToken, address to, uint128 amount)
        external
        payable
        returns (uint128 collateralReceived);

    /// @notice Closes a vault and withdraws remaining collateral
    /// @param debtToken Address of the debt token
    /// @param to Address to receive the withdrawn collateral
    /// @return collateralReceived The amount of collateral received in exchange
    function close(address debtToken, address to) external payable returns (uint128 collateralReceived);

    /// @notice Updates the oracle with new price data
    /// @param data Encoded oracle update data
    function updateOracle(bytes calldata data) external payable;

    /// @notice Allows a user to approve a spender to spend their tokens
    /// @param token Address of the token to approve
    /// @param value Amount of tokens to approve
    /// @param deadline Timestamp after which the approval is no longer valid
    /// @param v ECDSA signature component
    /// @param r ECDSA signature component
    /// @param s ECDSA signature component
    function permit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external payable;
}
