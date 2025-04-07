// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {Diamond} from "diamond/storages/Diamond.sol";

contract Init {
    function init() external {
        Diamond.Storage storage ds = Diamond.load();
        ds.supportedInterfaces[type(IERC3156FlashLender).interfaceId] = true;
        ds.supportedInterfaces[0x7f5828d0] = true; // EIP173
    }
}
