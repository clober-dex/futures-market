// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IOracle {
    /// @notice Retrieves the number of decimals used by the oracle.
    /// @return The number of decimals.
    function decimals() external view returns (uint8);

    /// @notice Retrieves the price of a specified asset.
    /// @param assetId The identifier of the asset.
    /// @return The price of the asset.
    function getAssetPrice(bytes32 assetId) external view returns (uint256);

    /// @notice Retrieves the prices of a list of specified assets.
    /// @param assetIds The list of asset identifiers.
    /// @return The list of prices for the specified assets.
    function getAssetsPrices(bytes32[] calldata assetIds) external view returns (uint256[] memory);
}
