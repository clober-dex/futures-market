// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {LibOwnable} from "../libraries/LibOwnable.sol";

abstract contract Modifiers {
    modifier onlyOwner() {
        LibOwnable.checkOwner();
        _;
    }
}
