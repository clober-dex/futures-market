// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@pythnetwork/pyth-sdk-solidity/PythUtils.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IOracle} from "./interfaces/IOracle.sol";
import {IFallbackOracle} from "./interfaces/IFallbackOracle.sol";

contract PythOracle is IOracle, UUPSUpgradeable, Initializable, Ownable2Step {
    uint8 public constant decimals = 18;

    event PriceUpdateIntervalChanged(uint256 oldInterval, uint256 newInterval);

    IPyth public immutable pyth;
    mapping(address => bytes32) public getAssetId;
    uint256 public priceUpdateInterval;
    IFallbackOracle internal _fallbackOracle;

    constructor(address pyth_) Ownable(msg.sender) {
        pyth = IPyth(pyth_);
    }

    function initialize(address initialOwner) external initializer {
        _transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setPriceUpdateInterval(uint256 interval) external onlyOwner {
        uint256 oldInterval = priceUpdateInterval;
        priceUpdateInterval = interval;
        emit PriceUpdateIntervalChanged(oldInterval, interval);
    }

    function getAssetPrice(address asset) public view returns (uint256) {
        return getAssetPrice(getAssetId[asset]);
    }

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory results) {
        results = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            results[i] = getAssetPrice(assets[i]);
        }
        return results;
    }

    function getAssetPrice(bytes32 assetId) public view returns (uint256) {
        try pyth.getPriceNoOlderThan(assetId, priceUpdateInterval) returns (PythStructs.Price memory currentPrice) {
            return PythUtils.convertToUint(currentPrice.price, currentPrice.expo, decimals);
        } catch {
            if (address(_fallbackOracle) == address(0)) revert NoFallbackOracle();

            return _fallbackOracle.getValidPrice(assetId);
        }
    }

    function getAssetsPrices(bytes32[] calldata assetIds) external view returns (uint256[] memory prices) {
        prices = new uint256[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; ++i) {
            prices[i] = getAssetPrice(assetIds[i]);
        }
    }

    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }

    function updatePrice(bytes calldata data) external payable {
        bytes[] memory pythUpdateData = abi.decode(data, (bytes[]));
        uint256 updateFee = pyth.getUpdateFee(pythUpdateData);
        pyth.updatePriceFeeds{value: updateFee}(pythUpdateData);
    }

    function setAssetId(address asset, bytes32 assetId) external onlyOwner {
        getAssetId[asset] = assetId;
        emit AssetIdSet(asset, assetId);
    }

    function setFallbackOracle(address newFallbackOracle) external onlyOwner {
        _fallbackOracle = IFallbackOracle(newFallbackOracle);
        emit SetFallbackOracle(newFallbackOracle);
    }
}
