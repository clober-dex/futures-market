// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/FallbackOracle.sol";
import {IFallbackOracle} from "../src/interfaces/IFallbackOracle.sol";

contract FallbackOracleTest is Test {
    FallbackOracle public implementation;
    FallbackOracle public oracle;
    address public owner;
    address public nonOwner;
    address public operator;
    bytes32 constant ASSET_ID = keccak256("TEST_ASSET");
    uint256 constant PRICE = 123 * 1e18;
    uint256 constant MAX_AGE = 1 hours;

    function setUp() public {
        owner = address(this);
        nonOwner = address(0xBEEF);
        operator = address(0xCAFE);
        implementation = new FallbackOracle();
        oracle = FallbackOracle(
            address(
                new ERC1967Proxy(
                    address(implementation), abi.encodeWithSelector(FallbackOracle.initialize.selector, owner)
                )
            )
        );
        oracle.setPriceMaxAge(MAX_AGE);
    }

    function test_initialize_setsOwner() public view {
        assertEq(oracle.owner(), owner);
    }

    function test_setOperator_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.setOperator(operator, true);
    }

    function test_setOperator_and_event() public {
        vm.expectEmit(address(oracle));
        emit IFallbackOracle.OperatorSet(operator, true);
        oracle.setOperator(operator, true);
        assertTrue(oracle.isOperator(operator));
    }

    function test_updatePrice_onlyOperator() public {
        vm.expectRevert(IFallbackOracle.NotOperator.selector);
        oracle.updatePrice(ASSET_ID, PRICE);
    }

    function test_updatePrice_and_getPriceData() public {
        oracle.setOperator(owner, true);
        uint256 before = block.timestamp;
        vm.expectEmit(address(oracle));
        emit IFallbackOracle.PriceUpdated(ASSET_ID, PRICE, block.timestamp);
        oracle.updatePrice(ASSET_ID, PRICE);
        (uint256 price, uint256 ts) = oracle.getPriceData(ASSET_ID);
        assertEq(price, PRICE);
        assertGe(ts, before);
        assertLe(ts, block.timestamp);
    }

    function test_getPriceData_tooOld() public {
        oracle.setOperator(owner, true);
        oracle.updatePrice(ASSET_ID, PRICE);
        vm.warp(block.timestamp + MAX_AGE + 1);
        vm.expectRevert(IFallbackOracle.PriceTooOld.selector);
        oracle.getPriceData(ASSET_ID);
    }

    function test_setPriceMaxAge_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.setPriceMaxAge(2 hours);
    }

    function test_setPriceMaxAge_and_event() public {
        uint256 newMaxAge = 2 hours;
        vm.expectEmit(address(oracle));
        emit IFallbackOracle.PriceMaxAgeSet(newMaxAge);
        oracle.setPriceMaxAge(newMaxAge);
        assertEq(oracle.priceMaxAge(), newMaxAge);
    }
}
