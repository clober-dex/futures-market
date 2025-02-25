// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IOracle {
    struct Price {
        uint256 price;
        uint32 decimals;
    }

    /// @notice Retrieves the price of a specified asset.
    /// @param assetId The identifier of the asset.
    /// @return The price of the asset.
    function getAssetPrice(bytes32 assetId) external view returns (Price memory);

    /// @notice Retrieves the prices of a list of specified assets.
    /// @param assetIds The list of asset identifiers.
    /// @return The list of prices for the specified assets.
    function getAssetsPrices(bytes32[] calldata assetIds) external view returns (Price[] memory);

    /// @notice Updates the oracle with new price data
    /// @param assetId The identifier of the asset
    /// @param data The new price data
    function updateOracle(bytes32 assetId, bytes calldata data) external;
}
