// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracle} from "../../src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    uint8 public constant override decimals = 18;

    mapping(address => bytes32) public getAssetId;
    mapping(bytes32 => uint256) public prices;

    function getAssetPrice(address asset) public view returns (uint256) {
        return prices[getAssetId[asset]];
    }

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory results) {
        results = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            results[i] = prices[getAssetId[assets[i]]];
        }
        return results;
    }

    function getAssetPrice(bytes32 assetId) external view returns (uint256) {
        return prices[assetId];
    }

    function getAssetsPrices(bytes32[] calldata assetIds) external view returns (uint256[] memory results) {
        results = new uint256[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            results[i] = prices[assetIds[i]];
        }
        return results;
    }

    function updateOracle(bytes32 assetId, bytes calldata data) external payable returns (uint256) {
        uint256 price = abi.decode(data, (uint256));
        prices[assetId] = price;
        emit OracleUpdated(assetId, price);
        return price;
    }

    function setAssetId(address asset, bytes32 assetId) external {
        getAssetId[asset] = assetId;
        emit AssetIdSet(asset, assetId);
    }
}
