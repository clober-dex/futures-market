// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IFallbackOracle} from "./interfaces/IFallbackOracle.sol";

contract FallbackOracle is IFallbackOracle, UUPSUpgradeable, Initializable, Ownable2Step {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }

    mapping(bytes32 => PriceData) private _priceData;
    mapping(address => bool) public isOperator;
    uint256 public priceMaxAge;

    modifier onlyOperator() {
        if (!isOperator[msg.sender]) revert NotOperator();
        _;
    }

    constructor() Ownable(msg.sender) {}

    function initialize(address initialOwner) external initializer {
        _transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getPriceData(bytes32 assetId) external view returns (uint256 price, uint256 timestamp) {
        PriceData memory data = _priceData[assetId];
        return (data.price, data.timestamp);
    }

    function getValidPrice(bytes32 assetId) external view returns (uint256 price) {
        PriceData memory data = _priceData[assetId];
        if (data.price == 0) revert PriceFeedNotFound();
        if (block.timestamp - data.timestamp > priceMaxAge) revert PriceTooOld();
        return data.price;
    }

    function getPricesData(bytes32[] calldata assetIds)
        external
        view
        returns (uint256[] memory prices, uint256[] memory timestamps)
    {
        prices = new uint256[](assetIds.length);
        timestamps = new uint256[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; ++i) {
            PriceData memory data = _priceData[assetIds[i]];
            prices[i] = data.price;
            timestamps[i] = data.timestamp;
        }
    }

    function updatePrice(bytes32 assetId, uint256 price) external onlyOperator {
        _priceData[assetId] = PriceData({price: price, timestamp: block.timestamp});
        emit PriceUpdated(assetId, price, block.timestamp);
    }

    function updatePrices(bytes32[] calldata assetIds, uint256[] calldata prices) external onlyOperator {
        require(assetIds.length == prices.length, "Length");
        for (uint256 i = 0; i < assetIds.length; ++i) {
            _priceData[assetIds[i]] = PriceData({price: prices[i], timestamp: block.timestamp});
            emit PriceUpdated(assetIds[i], prices[i], block.timestamp);
        }
    }

    function setOperator(address operator, bool status) external onlyOwner {
        isOperator[operator] = status;
        emit OperatorSet(operator, status);
    }

    function setPriceMaxAge(uint256 newMaxAge) external onlyOwner {
        priceMaxAge = newMaxAge;
        emit PriceMaxAgeSet(newMaxAge);
    }
}
