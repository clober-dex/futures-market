// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IDiamondApp} from "diamond/interfaces/IDiamondApp.sol";
import {IMarketManager} from "./IMarketManager.sol";
import {IMarketPosition} from "./IMarketPosition.sol";
import {IMarketView} from "./IMarketView.sol";
import {IUtils} from "./IUtils.sol";

/// @title Futures Market Interface
/// @notice Aggregates all interfaces required for the futures market functionality
/// @dev Implements diamond pattern interfaces along with market-specific functionality
interface IFuturesMarket is IDiamondApp, IMarketManager, IMarketPosition, IMarketView, IUtils {}
