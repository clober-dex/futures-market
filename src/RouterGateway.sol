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

    uint256 public constant FEE_PRECISION = 100_000; // 1e5
    uint256 public constant MAX_FEE_BPS = 100; // 0.1%

    mapping(address => mapping(bytes4 => bool)) public allowedRouterMethods;
    address public feeRecipient;

    error InvalidAmount();
    error RouterCallFailed(string reason);
    error TransferFailed();
    error MethodNotAllowed();
    error InsufficientAmountOut();
    error FeeTooHigh();
    error InvalidFeeRecipient();

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

    event FeeCollected(address indexed recipient, address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function initialize(address initialOwner, address initialFeeRecipient) external initializer {
        _transferOwnership(initialOwner);
        setFeeRecipient(initialFeeRecipient);
    }

    function setFeeRecipient(address newRecipient) public onlyOwner {
        if (newRecipient == address(0)) revert InvalidFeeRecipient();
        feeRecipient = newRecipient;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _calculateActualFee(uint256 amountOut, uint256 fee) internal pure returns (uint256) {
        uint256 maxFee = (amountOut * MAX_FEE_BPS) / FEE_PRECISION;
        uint256 actualFee = fee == 0 ? maxFee : fee;
        if (actualFee > maxFee) actualFee = maxFee;
        return actualFee;
    }

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

    function swap(
        address inToken,
        address outToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address router,
        bytes calldata data,
        uint256 fee
    ) external payable nonReentrant returns (uint256 amountOut) {
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

        amountOut = outToken == address(0)
            ? address(this).balance - amountOut
            : IERC20(outToken).balanceOf(address(this)) - amountOut;
        if (amountOut < minAmountOut) revert InsufficientAmountOut();

        uint256 actualFee = _calculateActualFee(amountOut, fee);
        uint256 amountToSend = amountOut - actualFee;

        if (outToken == address(0)) {
            (success,) = payable(msg.sender).call{value: amountToSend}("");
            if (!success) revert TransferFailed();

            if (actualFee > 0) {
                (success,) = payable(feeRecipient).call{value: actualFee}("");
                if (!success) revert TransferFailed();
            }
        } else {
            IERC20(outToken).safeTransfer(msg.sender, amountToSend);
            if (actualFee > 0) {
                IERC20(outToken).safeTransfer(feeRecipient, actualFee);
            }
        }

        emit Swap(msg.sender, inToken, outToken, amountIn, amountOut, router, method);

        if (actualFee > 0) {
            emit FeeCollected(feeRecipient, outToken, actualFee);
        }
    }

    receive() external payable {}
}
