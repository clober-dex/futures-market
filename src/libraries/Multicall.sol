// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract Multicall {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returndata) = address(this).delegatecall(data[i]);
            results[i] = Address.verifyCallResultFromTarget(address(this), success, returndata);
        }
        return results;
    }
}
