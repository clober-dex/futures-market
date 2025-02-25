// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracle} from "../../src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    mapping(bytes32 => Price) public prices;

    function getAssetPrice(bytes32 assetId) external view returns (Price memory) {
        return prices[assetId];
    }

    function getAssetsPrices(bytes32[] calldata assetIds) external view returns (Price[] memory results) {
        results = new Price[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            results[i] = prices[assetIds[i]];
        }
        return results;
    }

    function updateOracle(bytes32 assetId, bytes calldata data) external {
        Price memory price = abi.decode(data, (Price));
        prices[assetId] = price;
    }
}
