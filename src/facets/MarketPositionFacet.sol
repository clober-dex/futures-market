// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {IMarketPosition} from "../interfaces/IMarketPosition.sol";
import {ILiquidator} from "../interfaces/ILiquidator.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {LibMarket} from "../libraries/LibMarket.sol";
import {LibOracle} from "../libraries/LibOracle.sol";
import {Market} from "../storages/Market.sol";
import {Debt} from "../Debt.sol";

contract MarketPositionFacet is IMarketPosition, ReentrancyGuardTransientUpgradeable {
    error InsufficientCollateral();
    error LTVExceeded();
    error BurnExceedsDebt();
    error PositionSafe();

    using SafeERC20 for IERC20;
    using LibMarket for Market.Storage;
    using LibOracle for IOracle;

    IOracle internal immutable _priceOracle;
    address internal immutable _debtTokenImplementation;

    constructor(address priceOracle_, address debtTokenImplementation_) {
        _priceOracle = IOracle(priceOracle_);
        _debtTokenImplementation = debtTokenImplementation_;
    }

    function deposit(address debtToken, address to, uint128 amount) external payable nonReentrant {
        Market.Storage storage market = Market.load(debtToken);
        market.checkUnsettled();

        IERC20(market.collateral).safeTransferFrom(msg.sender, address(this), amount);
        market.positions[to].collateral += amount;
        emit Deposit(debtToken, msg.sender, to, amount);
    }

    function withdraw(address debtToken, address to, uint128 amount) external payable nonReentrant {
        Market.Storage storage market = Market.load(debtToken);
        market.checkUnsettled();

        Market.Position memory position = market.positions[msg.sender];
        if (position.collateral < amount) revert InsufficientCollateral();
        unchecked {
            market.positions[msg.sender].collateral = position.collateral - amount;
        }
        uint256 relativePrice = _priceOracle.getRelativePrice(market.collateral, market.assetId);
        if (!market.isUnderLtv(msg.sender, relativePrice)) revert LTVExceeded();

        IERC20(market.collateral).safeTransfer(to, amount);
        emit Withdraw(debtToken, msg.sender, to, amount);
    }

    function mint(address debtToken, address to, uint128 amount) external payable nonReentrant {
        Market.Storage storage market = Market.load(debtToken);
        market.checkUnsettled();

        market.positions[msg.sender].debt += amount;
        uint256 relativePrice = _priceOracle.getRelativePrice(market.collateral, market.assetId);
        if (!market.isUnderLtv(msg.sender, relativePrice)) revert LTVExceeded();

        Debt(debtToken).mint(to, amount);
        emit Mint(debtToken, msg.sender, to, amount, relativePrice);
    }

    function burn(address debtToken, address to, uint128 amount) external payable nonReentrant {
        Market.Storage storage market = Market.load(debtToken);
        market.checkUnsettled();

        Market.Position memory position = market.positions[to];
        if (position.debt < amount) revert BurnExceedsDebt();

        Debt(debtToken).burn(msg.sender, amount);
        unchecked {
            market.positions[to].debt = position.debt - amount;
        }
        emit Burn(debtToken, msg.sender, to, amount);
    }

    function liquidate(address debtToken, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        payable
        nonReentrant
        returns (uint128 debtCovered, uint128 collateralLiquidated)
    {
        Market.Storage storage market = Market.load(debtToken);
        market.checkUnsettled();

        uint256 relativePrice = _priceOracle.getRelativePrice(market.collateral, market.assetId);
        if (market.isPositionSafe(user, relativePrice)) revert PositionSafe();

        Market.Position memory position = market.positions[user];
        if (position.debt < debtToCover) {
            debtCovered = position.debt;
            collateralLiquidated = position.collateral;
        } else {
            debtCovered = debtToCover;
            collateralLiquidated = uint128(uint256(position.collateral) * debtCovered / position.debt);
        }
        unchecked {
            market.positions[user].debt = position.debt - debtCovered;
            market.positions[user].collateral = position.collateral - collateralLiquidated;
        }

        IERC20(market.collateral).safeTransfer(msg.sender, collateralLiquidated);
        if (!skipCallback) {
            ILiquidator(msg.sender).onLiquidation(
                debtToken, user, debtCovered, collateralLiquidated, relativePrice, data
            );
        }
        Debt(debtToken).burn(msg.sender, debtCovered);

        emit Liquidate(debtToken, msg.sender, user, debtCovered, collateralLiquidated, relativePrice);
    }

    function redeem(address debtToken, address to, uint128 amount)
        external
        payable
        nonReentrant
        returns (uint128 collateralReceived)
    {
        Market.Storage storage market = Market.load(debtToken);
        market.checkSettled();

        Debt(debtToken).burn(msg.sender, amount);

        collateralReceived = market.calculateSettledCollateral(amount);
        IERC20(market.collateral).safeTransfer(to, collateralReceived);
        emit Redeem(debtToken, msg.sender, to, amount, collateralReceived);
    }

    function close(address debtToken, address to) external payable nonReentrant returns (uint128 collateralReceived) {
        Market.Storage storage market = Market.load(debtToken);
        market.checkSettled();

        Market.Position memory position = market.positions[msg.sender];
        unchecked {
            collateralReceived = position.collateral - market.calculateSettledCollateral(position.debt);
        }

        IERC20(market.collateral).safeTransfer(to, collateralReceived);
        delete market.positions[msg.sender];

        emit Close(debtToken, msg.sender, to, collateralReceived);
    }
}
