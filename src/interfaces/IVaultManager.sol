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
    /// @param id Unique identifier of the vault
    /// @param debt Address of the debt token created for this vault
    /// @param config Configuration parameters used to create the vault
    event Open(bytes32 indexed id, address indexed debt, Config config);

    /// @notice Emitted when collateral is deposited into a vault
    /// @param id Unique identifier of the vault
    /// @param depositor Address that initiated the deposit
    /// @param to Address that received the deposit credit
    /// @param amount Amount of collateral deposited
    event Deposit(bytes32 indexed id, address indexed depositor, address indexed to, uint128 amount);

    /// @notice Emitted when collateral is withdrawn from a vault
    /// @param id Unique identifier of the vault
    /// @param withdrawer Address that initiated the withdrawal
    /// @param to Address that received the withdrawn collateral
    /// @param amount Amount of collateral withdrawn
    event Withdraw(bytes32 indexed id, address indexed withdrawer, address indexed to, uint128 amount);

    /// @notice Emitted when debt tokens are minted
    /// @param id Unique identifier of the vault
    /// @param minter Address that initiated the mint
    /// @param to Address that received the minted tokens
    /// @param amount Amount of debt tokens minted
    event Mint(bytes32 indexed id, address indexed minter, address indexed to, uint128 amount);

    /// @notice Emitted when debt tokens are burned
    /// @param id Unique identifier of the vault
    /// @param burner Address that initiated the burn
    /// @param to Address that received credit for the burn
    /// @param amount Amount of debt tokens burned
    event Burn(bytes32 indexed id, address indexed burner, address indexed to, uint128 amount);

    /// @notice Emitted when a vault is settled at expiration
    /// @param id Unique identifier of the vault
    /// @param settlePrice The final settlement price used for the vault
    event Settle(bytes32 indexed id, uint256 settlePrice);

    /// @notice Emitted when a position is liquidated
    /// @param id Unique identifier of the vault
    /// @param liquidator Address that performed the liquidation
    /// @param user Address of the position owner that was liquidated
    /// @param debtCovered Amount of debt that was covered by the liquidation
    /// @param collateralLiquidated Amount of collateral that was liquidated
    event Liquidate(
        bytes32 indexed id,
        address indexed liquidator,
        address indexed user,
        uint128 debtCovered,
        uint128 collateralLiquidated
    );

    /// @notice Emitted when debt tokens are redeemed for collateral after settlement
    /// @param id Unique identifier of the vault
    /// @param redeemer Address that initiated the redemption
    /// @param to Address that received the collateral
    /// @param amount Amount of debt tokens redeemed
    /// @param collateralReceived Amount of collateral received in exchange
    event Redeem(
        bytes32 indexed id, address indexed redeemer, address indexed to, uint128 amount, uint128 collateralReceived
    );

    /// @notice Emitted when a vault is closed
    /// @param id Unique identifier of the vault
    /// @param closer Address that closed the vault
    /// @param to Address that received the collateral
    /// @param amount Amount of collateral withdrawn when closing the vault
    event Close(bytes32 indexed id, address indexed closer, address indexed to, uint128 amount);

    /// @notice Returns the address of the price oracle used by the vault manager
    /// @return oracle Address of the price oracle contract
    function priceOracle() external view returns (address oracle);

    /// @notice Calculates a unique identifier for a vault based on its parameters
    /// @param assetId Unique identifier for the underlying asset
    /// @param collateral Address of the collateral token
    /// @param expiration Timestamp when the vault expires
    /// @return id Unique vault identifier
    function encodeId(bytes32 assetId, address collateral, uint40 expiration) external pure returns (bytes32 id);

    /// @notice Retrieves the configuration for a specific vault
    /// @param id Unique identifier of the vault
    /// @return config Config struct containing vault parameters
    function getConfig(bytes32 id) external view returns (Config memory config);

    /// @notice Retrieves the position details for a specific user in a vault
    /// @param id Unique identifier of the vault
    /// @param user Address of the position owner
    /// @return position Position struct containing collateral and debt amounts
    function getPosition(bytes32 id, address user) external view returns (Position memory position);

    /// @notice Checks if a vault has been settled
    /// @param id Unique identifier of the vault
    /// @return settled True if the vault has been settled, false otherwise
    function isSettled(bytes32 id) external view returns (bool settled);

    /// @notice Returns the address of the debt token for a specific vault
    /// @param id Unique identifier of the vault
    /// @return debtToken Address of the debt token
    function getDebtToken(bytes32 id) external view returns (address debtToken);

    /// @notice Creates a new vault with the specified configuration
    /// @param config Configuration parameters for the new vault
    /// @param name Name of the debt token
    /// @param symbol Symbol of the debt token
    /// @return id Unique identifier of the new vault
    /// @return debtToken Address of the debt token
    function open(Config calldata config, string calldata name, string calldata symbol)
        external
        returns (bytes32 id, address debtToken);

    /// @notice Deposits collateral into a vault
    /// @param id Unique identifier of the vault
    /// @param to Address to credit the deposit to
    /// @param amount Amount of collateral to deposit
    function deposit(bytes32 id, address to, uint128 amount) external;

    /// @notice Withdraws collateral from a vault
    /// @param id Unique identifier of the vault
    /// @param to Address to receive the withdrawn collateral
    /// @param amount Amount of collateral to withdraw
    function withdraw(bytes32 id, address to, uint128 amount) external;

    /// @notice Mints debt tokens against deposited collateral
    /// @param id Unique identifier of the vault
    /// @param to Address to receive the minted debt tokens
    /// @param amount Amount of debt tokens to mint
    function mint(bytes32 id, address to, uint128 amount) external;

    /// @notice Burns debt tokens to reduce debt
    /// @param id Unique identifier of the vault
    /// @param to Address to credit the debt reduction to
    /// @param amount Amount of debt tokens to burn
    function burn(bytes32 id, address to, uint128 amount) external;

    /// @notice Settles a vault after expiration
    /// @param id Unique identifier of the vault
    /// @return settlePrice The final settlement price used for the vault
    function settle(bytes32 id) external returns (uint256 settlePrice);

    /// @notice Liquidates an undercollateralized position
    /// @param id Unique identifier of the vault
    /// @param user Address of the position owner to liquidate
    /// @param debtToCover Amount of debt to cover in the liquidation
    /// @param skipCallback Whether to skip the callback to the liquidator
    /// @param data Additional data for the liquidation
    /// @return debtCovered The actual amount of debt that was covered in the liquidation
    /// @return collateralLiquidated The amount of collateral that was liquidated
    function liquidate(bytes32 id, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        returns (uint128 debtCovered, uint128 collateralLiquidated);

    /// @notice Redeems debt tokens for collateral after settlement
    /// @param id Unique identifier of the vault
    /// @param to Address to receive the collateral
    /// @param amount Amount of debt tokens to redeem
    /// @return collateralReceived The amount of collateral received in exchange
    function redeem(bytes32 id, address to, uint128 amount) external returns (uint128 collateralReceived);

    /// @notice Closes a vault and withdraws remaining collateral
    /// @param id Unique identifier of the vault
    /// @param to Address to receive the withdrawn collateral
    /// @return collateralReceived The amount of collateral received in exchange
    function close(bytes32 id, address to) external returns (uint128 collateralReceived);

    /// @notice Updates the oracle with new price data
    /// @param assetId Unique identifier of the asset
    /// @param data Encoded oracle update data
    /// @return price The new price of the asset
    function updateOracle(bytes32 assetId, bytes calldata data) external payable returns (uint256 price);

    /// @notice Allows a user to approve a spender to spend their tokens
    /// @param token Address of the token to approve
    /// @param value Amount of tokens to approve
    /// @param deadline Timestamp after which the approval is no longer valid
    /// @param v ECDSA signature component
    /// @param r ECDSA signature component
    /// @param s ECDSA signature component
    function permit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}
