// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IFuturesMarket} from "../../src/interfaces/IFuturesMarket.sol";
import {ILiquidator} from "../../src/interfaces/ILiquidator.sol";

contract MockLiquidator is ILiquidator {
    IFuturesMarket public immutable manager;

    bytes32 public flag;

    constructor(IFuturesMarket manager_) {
        manager = manager_;
    }

    function liquidate(address debtToken, address user, uint128 debtCovered, bytes calldata data)
        external
        returns (uint128, uint128)
    {
        return manager.liquidate(debtToken, user, debtCovered, false, data);
    }

    function onLiquidation(
        address debtToken,
        address user,
        uint128 debtCovered,
        uint128 collateralLiquidated,
        uint256 relativePrice,
        bytes calldata data
    ) external {
        require(msg.sender == address(manager), "MockLiquidator: unauthorized");
        flag = keccak256(abi.encode(debtToken, user, debtCovered, collateralLiquidated, relativePrice, data));
        IERC20(debtToken).approve(address(manager), debtCovered);
    }
}
