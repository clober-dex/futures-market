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
        if (block.timestamp - data.timestamp > priceMaxAge) revert PriceTooOld();
        return (data.price, data.timestamp);
    }

    function updatePrice(bytes32 assetId, uint256 price) external onlyOperator {
        _priceData[assetId] = PriceData({
            price: price,
            timestamp: block.timestamp
        });

        emit PriceUpdated(assetId, price, block.timestamp);
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
