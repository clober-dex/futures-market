// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Ownership {
    struct Storage {
        address owner;
        address pendingOwner;
    }

    // bytes32(uint256(keccak256('app.storage.Ownable')) - 1)
    bytes32 internal constant POSITION = 0x781af69b8a39034671c420950921efe813f55295c4d49895e31f5d65ee1b0a75;

    function load() internal pure returns (Storage storage $) {
        assembly {
            $.slot := POSITION
        }
    }
}
