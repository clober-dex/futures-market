// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";

library LibOracle {
    uint256 internal constant PRECISION = 1e18;

    function getRelativePrice(IOracle oracle, address collateral, bytes32 assetId) internal view returns (uint256) {
        uint256 collateralPrice = oracle.getAssetPrice(collateral);
        uint256 debtPrice = oracle.getAssetPrice(assetId);
        return debtPrice * PRECISION / collateralPrice;
    }
}
