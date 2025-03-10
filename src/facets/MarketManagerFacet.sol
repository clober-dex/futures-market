// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {InvalidConfig, NotExpired} from "../Errors.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Ownable} from "./Ownable.sol";
import {Market} from "../storages/Market.sol";
import {Debt} from "../Debt.sol";
import {LibMarket} from "../libraries/LibMarket.sol";
import {LibOracle} from "../libraries/LibOracle.sol";

contract MarketManagerFacet is IMarketManager, Ownable {
    using LibOracle for IOracle;
    using LibMarket for Market.Storage;

    IOracle internal immutable _priceOracle;
    address internal immutable _debtTokenImplementation;

    constructor(address priceOracle_, address debtTokenImplementation_) {
        _priceOracle = IOracle(priceOracle_);
        _debtTokenImplementation = debtTokenImplementation_;
    }

    function open(
        bytes32 assetId,
        address collateral,
        uint40 expiration,
        uint24 ltv,
        uint24 liquidationThreshold,
        uint128 minDebt,
        string calldata name,
        string calldata symbol
    ) external payable onlyOwner returns (address debtToken) {
        if (expiration < block.timestamp) revert InvalidConfig();
        if (ltv > liquidationThreshold) revert InvalidConfig();
        if (ltv > LibMarket.RATE_PRECISION) revert InvalidConfig();
        if (liquidationThreshold > LibMarket.RATE_PRECISION) revert InvalidConfig();

        bytes32 salt = keccak256(abi.encode(assetId, collateral, expiration));
        debtToken = Clones.cloneDeterministic(_debtTokenImplementation, salt);
        Debt(debtToken).initialize(name, symbol);

        Market.Storage storage market = Market.load(debtToken);
        market.assetId = assetId;
        market.collateral = collateral;
        market.expiration = expiration;
        market.ltv = ltv;
        market.liquidationThreshold = liquidationThreshold;
        market.minDebt = minDebt;

        emit Open(debtToken, assetId, collateral, expiration, ltv, liquidationThreshold, minDebt);
    }

    function settle(address debtToken) external payable returns (uint256 settlePrice) {
        Market.Storage storage market = Market.load(debtToken);
        market.checkUnsettled();
        if (block.timestamp < market.expiration) revert NotExpired();

        settlePrice = _priceOracle.getRelativePrice(market.collateral, market.assetId);
        market.settlePrice = settlePrice;
        emit Settle(debtToken, settlePrice);
    }

    function updateOracle(bytes calldata data) external payable {
        _priceOracle.updatePrice{value: msg.value}(data);
    }
}
