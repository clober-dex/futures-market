// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Fallback Oracle Interface
/// @notice Interface for a fallback oracle that provides price data with timestamps
/// @dev Used as a backup price source when the primary oracle fails
interface IFallbackOracle {
    /// @notice Error thrown when a non-operator tries to update prices
    error NotOperator();

    /// @notice Error thrown when a price is too old
    error PriceTooOld();

    /// @notice Error thrown when a price feed is not found
    error PriceFeedNotFound();

    /// @notice Emitted when a price is updated by an operator
    /// @param assetId The identifier of the asset
    /// @param price The new price of the asset
    /// @param timestamp The timestamp when the price was updated
    event PriceUpdated(bytes32 indexed assetId, uint256 price, uint256 timestamp);

    /// @notice Emitted when an operator's status is changed
    /// @param operator The address of the operator
    /// @param status The new operator status
    event OperatorSet(address indexed operator, bool status);

    /// @notice Emitted when the price max age is set
    /// @param newMaxAge The new maximum age for prices
    event PriceMaxAgeSet(uint256 newMaxAge);

    /// @notice Returns the maximum allowed age for prices
    /// @return The maximum age in seconds that a price can be considered valid
    function priceMaxAge() external view returns (uint256);

    /// @notice Checks if an address is an operator
    /// @param operator The address to check
    /// @return True if the address is an operator, false otherwise
    function isOperator(address operator) external view returns (bool);

    /// @notice Returns the price data for a given asset ID
    /// @param assetId The identifier of the asset
    /// @return price The price of the asset
    /// @return timestamp The timestamp when the price was last updated
    function getPriceData(bytes32 assetId) external view returns (uint256 price, uint256 timestamp);

    /// @notice Returns the price data for multiple asset IDs
    /// @param assetIds The identifiers of the assets
    /// @return prices The prices of the assets
    /// @return timestamps The timestamps when the prices were last updated
    function getPricesData(bytes32[] calldata assetIds)
        external
        view
        returns (uint256[] memory prices, uint256[] memory timestamps);

    /// @notice Updates the price for a given asset ID
    /// @param assetId The identifier of the asset
    /// @param price The new price of the asset
    function updatePrice(bytes32 assetId, uint256 price) external;

    /// @notice Updates the prices for multiple asset IDs
    /// @param assetIds The identifiers of the assets
    /// @param prices The new prices of the assets
    function updatePrices(bytes32[] calldata assetIds, uint256[] calldata prices) external;

    /// @notice Sets or revokes operator status for an address
    /// @param operator The address to set operator status for
    /// @param status True to grant operator status, false to revoke
    function setOperator(address operator, bool status) external;

    /// @notice Sets the maximum age for prices
    /// @param newMaxAge The new maximum age for prices
    function setPriceMaxAge(uint256 newMaxAge) external;

    /// @notice Returns the price for a given asset ID, reverts if not found or too old
    /// @param assetId The identifier of the asset
    /// @return price The price of the asset (reverts if not found or too old)
    function getValidPrice(bytes32 assetId) external view returns (uint256 price);
}
