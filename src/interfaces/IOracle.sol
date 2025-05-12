// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Oracle Interface for Asset Price Data
/// @notice Interface for retrieving and updating asset price data
/// @dev Handles price data for both address-based and ID-based asset identification
interface IOracle {
    /// @notice Error thrown when a fallback oracle is not set
    error NoFallbackOracle();

    /// @notice Emitted when the asset identifier is set.
    /// @param asset The address of the asset.
    /// @param assetId The identifier of the asset.
    event AssetIdSet(address indexed asset, bytes32 assetId);

    /// @notice Emitted when the fallback oracle is set.
    /// @param newFallbackOracle The address of the fallback oracle.
    event SetFallbackOracle(address indexed newFallbackOracle);

    /// @notice Retrieves the number of decimals used by the oracle.
    /// @return The number of decimals.
    function decimals() external view returns (uint8);

    /// @notice Retrieves the price of a specified asset.
    /// @param asset The address of the asset.
    /// @return The price of the asset.
    function getAssetPrice(address asset) external view returns (uint256);

    /// @notice Retrieves the prices of a list of specified assets.
    /// @param assets The list of asset addresses.
    /// @return The list of prices for the specified assets.
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    /// @notice Retrieves the price of a specified asset.
    /// @param assetId The identifier of the asset.
    /// @return The price of the asset.
    function getAssetPrice(bytes32 assetId) external view returns (uint256);

    /// @notice Retrieves the prices of a list of specified assets.
    /// @param assetIds The list of asset identifiers.
    /// @return The list of prices for the specified assets.
    function getAssetsPrices(bytes32[] calldata assetIds) external view returns (uint256[] memory);

    /// @notice Updates the oracle with new price data
    /// @param data The new price data
    function updatePrice(bytes calldata data) external payable;

    /// @notice Retrieves the asset identifier for a given asset.
    /// @param asset The address of the asset.
    /// @return The identifier of the asset.
    function getAssetId(address asset) external view returns (bytes32);

    /// @notice Retrieves the fallback oracle.
    /// @return The address of the fallback oracle.
    function getFallbackOracle() external view returns (address);

    /// @notice Sets the asset identifier for a given asset.
    /// @param asset The address of the asset.
    /// @param assetId The identifier of the asset.
    function setAssetId(address asset, bytes32 assetId) external;

    /// @notice Sets the fallback oracle.
    /// @param newFallbackOracle The address of the fallback oracle.
    function setFallbackOracle(address newFallbackOracle) external;
}
