// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import "../src/PythOracle.sol";
import "../src/FallbackOracle.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IFallbackOracle} from "../src/interfaces/IFallbackOracle.sol";

contract PythOracleTest is Test {
    PythOracle public implementation;
    PythOracle public oracle;
    FallbackOracle public fallbackOracle;
    address public pyth;
    address public owner;
    address public nonOwner;

    bytes32 constant ASSET_ID = keccak256("TEST_ASSET");
    address constant ASSET = address(0x1234);
    uint256 constant PRICE = 100 * 1e18;
    uint256 constant PRICE_UPDATE_INTERVAL = 1 hours;

    function setUp() public {
        owner = address(this);
        nonOwner = address(0xBEEF);
        pyth = address(0xCAFE);

        // Deploy implementation and proxy
        implementation = new PythOracle(pyth);
        oracle = PythOracle(address(new ERC1967Proxy(address(implementation), abi.encodeWithSelector(PythOracle.initialize.selector, owner))));
        oracle.setPriceUpdateInterval(PRICE_UPDATE_INTERVAL);

        // Deploy fallback oracle implementation and proxy
        FallbackOracle fallbackImpl = new FallbackOracle();
        fallbackOracle = FallbackOracle(address(new ERC1967Proxy(address(fallbackImpl), abi.encodeWithSelector(FallbackOracle.initialize.selector, owner))));
    }

    function test_initialization() public view {
        assertEq(address(oracle.pyth()), pyth);
        assertEq(oracle.priceUpdateInterval(), PRICE_UPDATE_INTERVAL);
        assertEq(oracle.owner(), owner);
    }

    function test_getAssetPrice_fromFallback() public {
        oracle.setAssetId(ASSET, ASSET_ID);
        oracle.setFallbackOracle(address(fallbackOracle));

        // Mock Pyth to revert
        vm.mockCallRevert(
            pyth,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ASSET_ID, PRICE_UPDATE_INTERVAL),
            "Price too old"
        );

        // Set fallback price
        fallbackOracle.setOperator(address(this), true);
        fallbackOracle.updatePrice(ASSET_ID, PRICE);

        uint256 result = oracle.getAssetPrice(ASSET);
        assertEq(result, PRICE);
    }

    function test_getAssetPrice_noFallback() public {
        oracle.setAssetId(ASSET, ASSET_ID);

        // Mock Pyth to revert
        vm.mockCallRevert(
            pyth,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ASSET_ID, PRICE_UPDATE_INTERVAL),
            "Price too old"
        );

        vm.expectRevert(IOracle.NoFallbackOracle.selector);
        oracle.getAssetPrice(ASSET);
    }

    function test_updatePrice() public {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = abi.encode(ASSET_ID, PRICE);

        // Mock Pyth update fee
        vm.mockCall(
            pyth,
            abi.encodeWithSelector(IPyth.getUpdateFee.selector, updateData),
            abi.encode(0.001 ether)
        );

        // Mock Pyth update price feeds
        vm.mockCall(
            pyth,
            abi.encodeWithSelector(IPyth.updatePriceFeeds.selector, updateData),
            ""
        );

        oracle.updatePrice{value: 0.001 ether}(abi.encode(updateData));
    }

    function test_setAssetId() public {
        vm.expectEmit(address(oracle));
        emit IOracle.AssetIdSet(ASSET, ASSET_ID);
        oracle.setAssetId(ASSET, ASSET_ID);
        assertEq(oracle.getAssetId(ASSET), ASSET_ID);
    }

    function test_setFallbackOracle() public {
        vm.expectEmit(address(oracle));
        emit IOracle.SetFallbackOracle(address(fallbackOracle));
        oracle.setFallbackOracle(address(fallbackOracle));
        assertEq(oracle.getFallbackOracle(), address(fallbackOracle));
    }

    function test_setPriceUpdateInterval() public {
        uint256 newInterval = 2 hours;
        vm.expectEmit(address(oracle));
        emit PythOracle.PriceUpdateIntervalChanged(PRICE_UPDATE_INTERVAL, newInterval);
        oracle.setPriceUpdateInterval(newInterval);
        assertEq(oracle.priceUpdateInterval(), newInterval);
    }

    function test_setAssetId_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.setAssetId(ASSET, ASSET_ID);
    }

    function test_setFallbackOracle_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.setFallbackOracle(address(fallbackOracle));
    }

    function test_setPriceUpdateInterval_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.setPriceUpdateInterval(2 hours);
    }

    function test_getAssetPrice_staleFallbackPrice() public {
        oracle.setAssetId(ASSET, ASSET_ID);
        oracle.setFallbackOracle(address(fallbackOracle));

        // Mock Pyth to revert
        vm.mockCallRevert(
            pyth,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ASSET_ID, PRICE_UPDATE_INTERVAL),
            "Price too old"
        );

        // Set fallback price with old timestamp
        fallbackOracle.setOperator(address(this), true);
        fallbackOracle.updatePrice(ASSET_ID, PRICE);
        vm.warp(block.timestamp + PRICE_UPDATE_INTERVAL + 1);

        vm.expectRevert(IFallbackOracle.PriceTooOld.selector);
        oracle.getAssetPrice(ASSET);
    }
} 