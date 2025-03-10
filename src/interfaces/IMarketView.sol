// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IMarketView {
    struct Market {
        bytes32 assetId;
        address collateral;
        uint40 expiration;
        uint24 ltv;
        uint24 liquidationThreshold;
        uint128 minDebt;
        uint256 settlePrice;
    }

    function getMarket(address debtToken) external view returns (Market memory market);

    function getPosition(address debtToken, address user) external view returns (uint128 collateral, uint128 debt);

    function isSettled(address debtToken) external view returns (bool settled);
}
