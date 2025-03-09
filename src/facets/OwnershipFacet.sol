// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {LibOwnable} from "../libraries/LibOwnable.sol";
import {IOwnable} from "../interfaces/IOwnable.sol";
import {Modifiers} from "./Modifiers.sol";

contract OwnershipFacet is IOwnable, Modifiers {
    error OwnableUnauthorizedAccount(address account);

    function owner() external view returns (address owner_) {
        owner_ = LibOwnable.owner();
    }

    function pendingOwner() external view returns (address pendingOwner_) {
        pendingOwner_ = LibOwnable.pendingOwner();
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = LibOwnable.owner();
        LibOwnable.setPendingOwner(address(0));
        LibOwnable.setOwner(newOwner);
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function renounceOwnership() external onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        LibOwnable.setPendingOwner(newOwner);
        emit OwnershipTransferStarted(LibOwnable.owner(), newOwner);
    }

    function acceptOwnership() external {
        address sender = msg.sender;
        if (LibOwnable.pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}
