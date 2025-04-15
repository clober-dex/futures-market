// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract RouterGateway is UUPSUpgradeable, Ownable2Step, Initializable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    mapping(address => mapping(bytes4 => bool)) public allowedRouterMethods;

    error InvalidAmount();
    error RouterCallFailed(string reason);
    error TransferFailed();
    error MethodNotAllowed();
    error InsufficientAmountOut();

    event RouterMethodAdded(address indexed router, bytes4 method);
    event RouterMethodRemoved(address indexed router, bytes4 method);
    event Swap(
        address indexed user,
        address indexed inToken,
        address indexed outToken,
        uint256 amountIn,
        uint256 amountOut,
        address router,
        bytes4 method
    );

    constructor() Ownable(msg.sender) {}

    function initialize(address initialOwner) external initializer {
        _transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function addRouterMethod(address router, bytes4 method) external onlyOwner {
        allowedRouterMethods[router][method] = true;
        emit RouterMethodAdded(router, method);
    }

    function removeRouterMethod(address router, bytes4 method) external onlyOwner {
        allowedRouterMethods[router][method] = false;
        emit RouterMethodRemoved(router, method);
    }

    function withdraw(address token, uint256 amount, address recipient) external onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(recipient).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    function swap(address inToken, address outToken, uint256 amountIn, uint256 minAmountOut, address router, bytes calldata data)
        external
        payable
        nonReentrant
        returns (uint256 amountOut)
    {
        bytes4 method = bytes4(data[0:4]);
        if (!allowedRouterMethods[router][method]) revert MethodNotAllowed();

        if (inToken == address(0)) {
            if (msg.value != amountIn) revert InvalidAmount();
        } else {
            IERC20(inToken).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(inToken).forceApprove(router, amountIn);
        }

        if (outToken == address(0)) {
            amountOut = address(this).balance;
        } else {
            amountOut = IERC20(outToken).balanceOf(address(this));
        }

        (bool success, bytes memory result) = address(router).call{value: msg.value}(data);
        if (!success) revert RouterCallFailed(string(result));

        if (inToken != address(0)) {
            IERC20(inToken).forceApprove(router, 0);
        }

        if (outToken == address(0)) {
            amountOut = address(this).balance - amountOut;
            if (amountOut < minAmountOut) revert InsufficientAmountOut();
            (success,) = payable(msg.sender).call{value: amountOut}("");
            if (!success) revert TransferFailed();
        } else {
            amountOut = IERC20(outToken).balanceOf(address(this)) - amountOut;
            if (amountOut < minAmountOut) revert InsufficientAmountOut();
            IERC20(outToken).safeTransfer(msg.sender, amountOut);
        }

        emit Swap(msg.sender, inToken, outToken, amountIn, amountOut, router, method);
    }

    receive() external payable {}
}
