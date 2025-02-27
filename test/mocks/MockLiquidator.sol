// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {ILiquidator} from "../../src/interfaces/ILiquidator.sol";

contract MockLiquidator is ILiquidator {
    IVaultManager public immutable manager;

    bytes32 public flag;

    constructor(IVaultManager manager_) {
        manager = manager_;
    }

    function liquidate(bytes32 id, address user, uint128 debtCovered, bytes calldata data)
        external
        returns (uint128, uint128)
    {
        return manager.liquidate(id, user, debtCovered, false, data);
    }

    function onLiquidation(
        bytes32 id,
        address caller,
        address user,
        uint128 debtCovered,
        uint128 collateralLiquidated,
        uint256 relativePrice,
        bytes calldata data
    ) external {
        require(msg.sender == address(manager), "MockLiquidator: unauthorized");
        flag = keccak256(abi.encode(id, caller, user, debtCovered, collateralLiquidated, relativePrice, data));
        IERC20(manager.getDebtToken(id)).approve(address(manager), debtCovered);
    }
}
