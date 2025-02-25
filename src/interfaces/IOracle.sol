// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IOracle {
    /// @notice Emitted when the oracle is updated.
    /// @param assetId The identifier of the asset.
    /// @param price The new price of the asset.
    event OracleUpdated(bytes32 indexed assetId, uint256 price);

    /// @notice Emitted when the asset identifier is set.
    /// @param asset The address of the asset.
    /// @param assetId The identifier of the asset.
    event AssetIdSet(address indexed asset, bytes32 assetId);

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
    /// @param assetId The identifier of the asset
    /// @param data The new price data
    function updateOracle(bytes32 assetId, bytes calldata data) external payable returns (uint256 price);

    /// @notice Retrieves the asset identifier for a given asset.
    /// @param asset The address of the asset.
    /// @return The identifier of the asset.
    function getAssetId(address asset) external view returns (bytes32);

    /// @notice Sets the asset identifier for a given asset.
    /// @param asset The address of the asset.
    /// @param assetId The identifier of the asset.
    function setAssetId(address asset, bytes32 assetId) external;
}
