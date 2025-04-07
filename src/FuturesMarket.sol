// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {DiamondApp} from "diamond/DiamondApp.sol";

contract FuturesMarket is DiamondApp {
    constructor(address _owner) DiamondApp(_owner) {}
}
