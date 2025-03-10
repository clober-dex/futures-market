// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Ownership {
    struct Storage {
        address owner;
        address pendingOwner;
    }

    // bytes32(uint256(keccak256('app.storage.Ownership')) - 1)
    bytes32 internal constant POSITION = 0x4e4ebbee0be3d30f69e31aa5e260d7a7f722e0c4bfe0fa8e2107c8a7763f5367;

    function load() internal pure returns (Storage storage $) {
        assembly {
            $.slot := POSITION
        }
    }
}
