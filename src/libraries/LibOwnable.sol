// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library LibOwnable {
    error OwnableUnauthorizedAccount(address account);

    struct OwnableStorage {
        address owner;
        address pendingOwner;
    }

    // keccak256("app.storage.Ownable") - 1
    // bytes32(uint256(keccak256('app.storage.Ownable')) - 1)
    bytes32 constant OWNABLE_STORAGE_POSITION = 0x781af69b8a39034671c420950921efe813f55295c4d49895e31f5d65ee1b0a75;

    function _getStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OWNABLE_STORAGE_POSITION
        }
    }

    function owner() internal view returns (address owner_) {
        owner_ = _getStorage().owner;
    }

    function pendingOwner() internal view returns (address pendingOwner_) {
        pendingOwner_ = _getStorage().pendingOwner;
    }

    function checkOwner() internal view {
        if (msg.sender != _getStorage().owner) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    function setOwner(address newOwner) internal {
        OwnableStorage storage $ = _getStorage();
        $.owner = newOwner;
    }

    function setPendingOwner(address newPendingOwner) internal {
        OwnableStorage storage $ = _getStorage();
        $.pendingOwner = newPendingOwner;
    }
}
