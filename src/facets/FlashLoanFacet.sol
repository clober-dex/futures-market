// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC3156FlashLender, IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {InvalidFlashLoanCallback} from "../Errors.sol";

contract FlashLoanFacet is IERC3156FlashLender {
    using SafeERC20 for IERC20;

    bytes32 internal constant CALLBACK_MAGIC_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    function maxFlashLoan(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function flashFee(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        IERC20(token).safeTransfer(address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, 0, data) != CALLBACK_MAGIC_VALUE) {
            revert InvalidFlashLoanCallback();
        }
        IERC20(token).safeTransferFrom(address(receiver), address(this), amount);
        return true;
    }
}
