// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IMarketView} from "../interfaces/IMarketView.sol";
import {Market as MarketStorage} from "../storages/Market.sol";
import {LibMarket} from "../libraries/LibMarket.sol";

contract MarketViewerFacet is IMarketView {
    using LibMarket for MarketStorage.Storage;

    function getMarket(address debtToken) external view returns (Market memory) {
        MarketStorage.Storage storage market_ = MarketStorage.load(debtToken);
        return Market({
            assetId: market_.assetId,
            collateral: market_.collateral,
            expiration: market_.expiration,
            ltv: market_.ltv,
            liquidationThreshold: market_.liquidationThreshold,
            minDebt: market_.minDebt,
            settlePrice: market_.settlePrice
        });
    }

    function getPosition(address debtToken, address user) external view returns (uint128 collateral, uint128 debt) {
        MarketStorage.Position memory position = MarketStorage.load(debtToken).positions[user];
        return (position.collateral, position.debt);
    }

    function isSettled(address debtToken) external view returns (bool) {
        return MarketStorage.load(debtToken).isSettled();
    }
}
