// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IDiamondCut} from "./IDiamondCut.sol";
import {IDiamondLoupe} from "./IDiamondLoupe.sol";
import {IERC165} from "./IERC165.sol";
import {IMarketManager} from "./IMarketManager.sol";
import {IMarketPosition} from "./IMarketPosition.sol";
import {IMarketView} from "./IMarketView.sol";
import {IOwnership} from "./IOwnership.sol";
import {IUtils} from "./IUtils.sol";

interface IFuturesMarket is
    IDiamondCut,
    IDiamondLoupe,
    IERC165,
    IMarketManager,
    IMarketPosition,
    IMarketView,
    IOwnership,
    IUtils
{}
