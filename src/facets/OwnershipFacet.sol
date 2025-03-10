// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IOwnable} from "../interfaces/IOwnable.sol";
import {Modifiers} from "./Modifiers.sol";
import {Ownership} from "../storages/Ownership.sol";

contract OwnershipFacet is IOwnable, Modifiers {
    function owner() external view returns (address owner_) {
        owner_ = Ownership.load().owner;
    }

    function pendingOwner() external view returns (address pendingOwner_) {
        pendingOwner_ = Ownership.load().pendingOwner;
    }

    function _transferOwnership(address newOwner) internal {
        Ownership.Storage storage $ = Ownership.load();
        address oldOwner = $.owner;
        $.pendingOwner = address(0);
        $.owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function renounceOwnership() external onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        Ownership.Storage storage $ = Ownership.load();
        $.pendingOwner = newOwner;
        emit OwnershipTransferStarted($.owner, newOwner);
    }

    function acceptOwnership() external onlyPendingOwner {
        _transferOwnership(msg.sender);
    }
}
