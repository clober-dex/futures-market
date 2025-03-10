// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IUtils} from "../interfaces/IUtils.sol";

contract UtilsFacet is IUtils {
    function permit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external payable {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returndata) = address(this).delegatecall(data[i]);
            results[i] = Address.verifyCallResultFromTarget(address(this), success, returndata);
        }
        return results;
    }
}
