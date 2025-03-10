// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Market} from "../storages/Market.sol";
import {LibOracle} from "./LibOracle.sol";

library LibMarket {
    error MarketDoesNotExist();
    error AlreadySettled();
    error NotSettled();

    uint256 internal constant DEBT_PRECISION = 1e18;
    uint256 internal constant PRECISION = 1e6;

    function isSettled(Market.Storage storage market) internal view returns (bool) {
        return market.settlePrice != 0;
    }

    function _isUnderRatio(Market.Storage storage market, address user, uint256 relativePrice, uint256 ratio)
        internal
        view
        returns (bool)
    {
        uint256 collateralPrecision = 10 ** IERC20Metadata(market.collateral).decimals();
        Market.Position memory position = market.positions[user];
        return uint256(position.collateral) * ratio * LibOracle.PRECISION * DEBT_PRECISION
            > uint256(position.debt) * relativePrice * PRECISION * collateralPrecision;
    }

    function isUnderLtv(Market.Storage storage market, address user, uint256 relativePrice)
        internal
        view
        returns (bool)
    {
        return _isUnderRatio(market, user, relativePrice, market.ltv);
    }

    function isPositionSafe(Market.Storage storage market, address user, uint256 relativePrice)
        internal
        view
        returns (bool)
    {
        return _isUnderRatio(market, user, relativePrice, market.liquidationThreshold);
    }

    function checkUnsettled(Market.Storage storage market) internal view {
        if (market.assetId == bytes32(0)) revert MarketDoesNotExist();
        if (isSettled(market)) revert AlreadySettled();
    }

    function checkSettled(Market.Storage storage market) internal view {
        if (market.assetId == bytes32(0)) revert MarketDoesNotExist();
        if (!isSettled(market)) revert NotSettled();
    }

    function calculateSettledCollateral(Market.Storage storage market, uint128 amount)
        internal
        view
        returns (uint128)
    {
        uint256 collateralPrecision = 10 ** IERC20Metadata(market.collateral).decimals();
        return
            uint128(uint256(amount) * market.settlePrice * collateralPrecision / LibOracle.PRECISION / DEBT_PRECISION);
    }
}
