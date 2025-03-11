// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

import "../src/Errors.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {IFuturesMarket} from "../src/interfaces/IFuturesMarket.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IMarketPosition} from "../src/interfaces/IMarketPosition.sol";
import {IMarketManager} from "../src/interfaces/IMarketManager.sol";
import {IMarketView} from "../src/interfaces/IMarketView.sol";
import {LibMarket} from "../src/libraries/LibMarket.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockLiquidator} from "./mocks/MockLiquidator.sol";
import {Deploy} from "./Deploy.sol";
import {Deployer} from "../src/helpers/FacetDeployer.sol";

contract FuturesMarketTest is Test {
    using Deploy for Vm;

    IFuturesMarket public futuresMarket;
    IOracle public oracle;
    MockERC20 public collateral;
    MockLiquidator public liquidator;

    address constant RECEIVER = address(0x1234567890123456789012345678901234567890);
    address constant LIQUIDATOR = address(0x1234567890123456789012345678901234567891);

    bytes32 constant COLLATERAL_ASSET_ID = keccak256("COLLATERAL");
    bytes32 constant DEBT_ASSET_ID = keccak256("DEBT");
    uint40 constant FUTURE_EXPIRATION = 1699999999;

    function setUp() public {
        oracle = new MockOracle();
        collateral = new MockERC20("Mock Collateral", "MCK", 6);

        futuresMarket = vm.deployFuturesMarket(Deployer.wrap(address(this)), address(oracle), address(this));

        liquidator = new MockLiquidator(futuresMarket);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 300 * 1e18)); // $300
        oracle.setAssetId(address(collateral), COLLATERAL_ASSET_ID);
        oracle.updatePrice(abi.encode(COLLATERAL_ASSET_ID, 2 * 1e18)); // $2
    }

    struct MarketConfig {
        bytes32 assetId;
        address collateral;
        uint40 expiration;
        uint24 ltv;
        uint24 liquidationThreshold;
        uint128 minDebt;
    }

    function _defaultConfig() internal view returns (MarketConfig memory) {
        return MarketConfig({
            assetId: DEBT_ASSET_ID,
            collateral: address(collateral),
            expiration: FUTURE_EXPIRATION,
            ltv: 500000,
            liquidationThreshold: 750000,
            minDebt: 0.01 ether
        });
    }

    function _open(MarketConfig memory config) internal returns (address debtToken) {
        debtToken = futuresMarket.open(
            config.assetId,
            config.collateral,
            config.expiration,
            config.ltv,
            config.liquidationThreshold,
            config.minDebt,
            "DebtToken",
            "DBT"
        );
    }

    function test_open() public {
        MarketConfig memory config = _defaultConfig();
        vm.expectEmit(false, false, false, true);
        emit IMarketManager.Open(
            address(0),
            config.assetId,
            config.collateral,
            config.expiration,
            config.ltv,
            config.liquidationThreshold,
            config.minDebt
        );

        address debtToken = _open(config);
        assertTrue(debtToken != address(0));

        IFuturesMarket.Market memory stored = futuresMarket.getMarket(debtToken);
        assertEq(stored.assetId, config.assetId);
        assertEq(stored.collateral, config.collateral);
        assertEq(stored.expiration, config.expiration);
        assertEq(stored.ltv, config.ltv);
        assertEq(stored.liquidationThreshold, config.liquidationThreshold);
        assertEq(stored.minDebt, config.minDebt);
        assertEq(stored.settlePrice, 0);

        assertEq(IERC20Metadata(debtToken).name(), "DebtToken");
        assertEq(IERC20Metadata(debtToken).symbol(), "DBT");
    }

    function test_openInvalidConfig() public {
        MarketConfig memory cfg = _defaultConfig();

        cfg.ltv = 1e6 + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        _open(cfg);

        cfg = _defaultConfig();
        cfg.liquidationThreshold = 1e6 + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        _open(cfg);

        cfg = _defaultConfig();
        cfg.expiration = uint40(block.timestamp - 1);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        _open(cfg);

        cfg = _defaultConfig();
        cfg.liquidationThreshold = cfg.ltv - 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        _open(cfg);
    }

    function test_openDuplicate() public {
        _open(_defaultConfig());
        vm.expectRevert(abi.encodeWithSignature("FailedDeployment()"));
        _open(_defaultConfig());
    }

    function test_openOwnership() public {
        MarketConfig memory config = _defaultConfig();

        address nonOwner = address(0xBEEF);
        vm.startPrank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        _open(config);

        vm.stopPrank();
    }

    function test_deposit() public {
        MarketConfig memory config = _defaultConfig();
        address debtToken = _open(config);

        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Deposit(debtToken, address(this), RECEIVER, 50_000 * 1e6);

        futuresMarket.deposit(debtToken, RECEIVER, 50_000 * 1e6);

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, RECEIVER);
        assertEq(collateralAmount, 50_000 * 1e6, "collateral mismatch");
        assertEq(debtAmount, 0, "debt should remain 0");
        assertEq(
            collateral.balanceOf(address(futuresMarket)), 50_000 * 1e6, "futuresMarket collateral balance mismatch"
        );
    }

    function test_withdraw() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Withdraw(debtToken, address(this), RECEIVER, 50_000 * 1e6);

        futuresMarket.withdraw(debtToken, RECEIVER, 50_000 * 1e6);

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(collateralAmount, 50_000 * 1e6, "collateral mismatch after withdraw");
        assertEq(debtAmount, 0, "debt mismatch after withdraw");
        assertEq(collateral.balanceOf(RECEIVER), 50_000 * 1e6, "receiver collateral balance mismatch");
    }

    function test_withdrawInvalidAmount() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(InsufficientCollateral.selector));
        futuresMarket.withdraw(debtToken, address(this), 200_000 * 1e6);
    }

    function test_withdrawExceedsLtv() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        // Mint some debt so LTV is borderline
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        // Attempt to withdraw enough to exceed LTV
        vm.expectRevert(abi.encodeWithSelector(LTVExceeded.selector));
        futuresMarket.withdraw(debtToken, address(this), 90_000 * 1e6);
    }

    function test_mint() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Mint(debtToken, address(this), RECEIVER, 200 * 1e18, 150 * 1e18);

        futuresMarket.mint(debtToken, RECEIVER, 200 * 1e18);

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(debtAmount, 200 * 1e18, "debt mismatch after mint");
        assertEq(collateralAmount, 100_000 * 1e6, "collateral mismatch after mint");
        assertEq(IERC20(debtToken).balanceOf(RECEIVER), 200 * 1e18, "receiver debt balance mismatch");
    }

    function test_mintExceedsLtv() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(LTVExceeded.selector));
        futuresMarket.mint(debtToken, address(this), 400 * 1e18);
    }

    function test_burn() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        futuresMarket.mint(debtToken, RECEIVER, 100 * 1e18);

        // Expect burn event
        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Burn(debtToken, RECEIVER, address(this), 80 * 1e18);

        vm.prank(RECEIVER);
        futuresMarket.burn(debtToken, address(this), 80 * 1e18);

        (, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(debtAmount, 20 * 1e18, "debt mismatch after burn");
        assertEq(IERC20(debtToken).balanceOf(RECEIVER), 20 * 1e18, "debt balance mismatch after burn");
    }

    function test_burnExceedsDebt() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        futuresMarket.mint(debtToken, address(this), 40 * 1e18);

        // Attempt to burn more than minted
        vm.expectRevert(abi.encodeWithSelector(BurnExceedsDebt.selector));
        futuresMarket.burn(debtToken, address(this), 100 * 1e18);
    }

    function test_settle() public {
        address debtToken = _open(_defaultConfig());
        vm.warp(FUTURE_EXPIRATION + 1); // move time forward

        uint256 expectedSettlePrice = 150 * 1e18;

        vm.expectEmit(address(futuresMarket));
        emit IMarketManager.Settle(debtToken, expectedSettlePrice);

        uint256 settlePrice = futuresMarket.settle(debtToken);
        // Check that isSettled is now true
        assertTrue(futuresMarket.isSettled(debtToken), "Market should be settled");
        assertEq(settlePrice, expectedSettlePrice, "settlePrice mismatch");

        // Check that returned settlePrice is stored
        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        assertEq(market.settlePrice, settlePrice, "settlePrice mismatch");
    }

    function test_settleBeforeExpiration() public {
        address debtToken = _open(_defaultConfig());
        // Don't warp to the future
        vm.expectRevert(abi.encodeWithSelector(NotExpired.selector));
        futuresMarket.settle(debtToken);
    }

    function test_liquidate() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, LIQUIDATOR, 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 800 * 1e18));

        // Liquidator calls liquidate
        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Liquidate(debtToken, LIQUIDATOR, address(this), 80 * 1e18, 40_000 * 1e6, 400 * 1e18);

        vm.startPrank(LIQUIDATOR);
        (uint128 debtCovered, uint128 collateralLiquidated) =
            futuresMarket.liquidate(debtToken, address(this), 80 * 1e18, true, "");

        // Check the returned values
        assertEq(debtCovered, 80 * 1e18, "debtCovered mismatch");
        assertEq(collateralLiquidated, 40_000 * 1e6, "collateralLiquidated mismatch");

        // Check user's position now
        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(debtAmount, 120 * 1e18, "Remaining debt mismatch");
        assertEq(collateralAmount, 60_000 * 1e6, "Remaining collateral mismatch");
        assertEq(IERC20(debtToken).balanceOf(LIQUIDATOR), 120 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(LIQUIDATOR), 40_000 * 1e6, "collateral balance mismatch");
    }

    function test_liquidateSafePosition() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(PositionSafe.selector));
        futuresMarket.liquidate(debtToken, address(this), 200 * 1e18, true, "");
    }

    function test_liquidateExceedsDebt() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, LIQUIDATOR, 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 800 * 1e18));

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Liquidate(debtToken, LIQUIDATOR, address(this), 200 * 1e18, 100_000 * 1e6, 400 * 1e18);

        vm.startPrank(LIQUIDATOR);
        (uint128 debtCovered, uint128 collateralLiquidated) =
            futuresMarket.liquidate(debtToken, address(this), 240 * 1e18, true, "");
        assertEq(debtCovered, 200 * 1e18, "Should only cover up to actual debt");
        assertEq(collateralLiquidated, 100_000 * 1e6, "Should liquidate up to collateral");

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(debtAmount, 0, "Remaining debt mismatch");
        assertEq(collateralAmount, 0, "Remaining collateral mismatch");
        assertEq(IERC20(debtToken).balanceOf(LIQUIDATOR), 0, "debt balance mismatch");
        assertEq(collateral.balanceOf(LIQUIDATOR), 100_000 * 1e6, "collateral balance mismatch");
    }

    function test_liquidateWithInvalidCallback() public {
        // If liquidator != address(0) but doesn't implement onLiquidation
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        vm.expectRevert();
        futuresMarket.liquidate(debtToken, address(this), 100 * 1e18, false, "0x");
    }

    function test_liquidateCallback() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(liquidator), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 800 * 1e18));

        bytes memory callbackData = abi.encode("test data");
        bytes32 expectedFlag =
            keccak256(abi.encode(debtToken, address(this), 120 * 1e18, 60_000 * 1e6, 400 * 1e18, callbackData));

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Liquidate(
            debtToken, address(liquidator), address(this), 120 * 1e18, 60_000 * 1e6, 400 * 1e18
        );

        (uint128 debtCovered, uint128 collateralLiquidated) =
            liquidator.liquidate(debtToken, address(this), 120 * 1e18, callbackData);

        assertEq(debtCovered, 120 * 1e18, "debtCovered mismatch");
        assertEq(collateralLiquidated, 60_000 * 1e6, "collateralLiquidated mismatch");
        assertEq(liquidator.flag(), expectedFlag, "liquidator flag mismatch");

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(debtAmount, 80 * 1e18, "Remaining debt mismatch");
        assertEq(collateralAmount, 40_000 * 1e6, "Remaining collateral mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(liquidator)), 80 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(address(liquidator)), 60_000 * 1e6, "collateral balance mismatch");
    }

    function test_redeem() public {
        address debtToken = _open(_defaultConfig());
        // deposit + mint
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 400 * 1e18));

        // Advance time, settle
        vm.warp(FUTURE_EXPIRATION + 1);
        futuresMarket.settle(debtToken);

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Redeem(debtToken, address(this), RECEIVER, 100 * 1e18, 20_000 * 1e6);

        uint128 collateralReceived = futuresMarket.redeem(debtToken, RECEIVER, 100 * 1e18);
        assertEq(collateralReceived, 20_000 * 1e6, "collateralReceived mismatch (example value)");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 100 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(RECEIVER), 20_000 * 1e6, "collateral balance mismatch");

        // See it does not effect
        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 99999999 * 1e18));

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Redeem(debtToken, address(this), RECEIVER, 100 * 1e18, 20_000 * 1e6);

        collateralReceived = futuresMarket.redeem(debtToken, RECEIVER, 100 * 1e18);
        assertEq(collateralReceived, 20_000 * 1e6, "collateralReceived mismatch (example value)");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 0, "debt balance mismatch");
        assertEq(collateral.balanceOf(RECEIVER), 40_000 * 1e6, "collateral balance mismatch");
    }

    function test_close() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 400 * 1e18));

        // Move time forward, settle
        vm.warp(FUTURE_EXPIRATION + 1);
        futuresMarket.settle(debtToken);

        // If close() allows user to withdraw leftover collateral minus debt portion
        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Close(debtToken, address(this), RECEIVER, 60_000 * 1e6);

        uint128 collateralReceived = futuresMarket.close(debtToken, RECEIVER);
        assertEq(collateralReceived, 60_000 * 1e6, "collateralReceived mismatch");

        // Check that user's position is now zero
        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(collateralAmount, 0, "Position collateral should be 0 after close");
        assertEq(debtAmount, 0, "Position debt should be 0 after close");
        assertEq(collateral.balanceOf(RECEIVER), 60_000 * 1e6, "collateral balance mismatch");
    }

    function test_actionsWithInvalidId() public {
        address invalidAddress = address(0x1234567890123456789012345678901234567890);
        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.withdraw(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.deposit(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.mint(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.burn(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.liquidate(invalidAddress, address(this), 1, true, "");

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.redeem(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.close(invalidAddress, address(this));
    }

    function test_invalidActionsAfterSettlement() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.warp(FUTURE_EXPIRATION + 1);
        futuresMarket.settle(debtToken);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.deposit(debtToken, address(this), 1_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.withdraw(debtToken, address(this), 1_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.mint(debtToken, address(this), 10_000 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.burn(debtToken, address(this), 10_000 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.liquidate(debtToken, address(this), 10_000 * 1e18, true, "");
    }

    function test_invalidActionsBeforeSettlement() public {
        address debtToken = _open(_defaultConfig());

        vm.expectRevert(abi.encodeWithSelector(NotSettled.selector));
        futuresMarket.redeem(debtToken, address(this), 10_000 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(NotSettled.selector));
        futuresMarket.close(debtToken, address(this));
    }

    function test_updateOracle() public {
        bytes memory data = abi.encode(DEBT_ASSET_ID, 123456); // e.g. new price
        futuresMarket.updateOracle(data);

        assertEq(oracle.getAssetPrice(DEBT_ASSET_ID), 123456, "price mismatch");
    }

    function test_permit() public {
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        address owner = vm.addr(1);
        collateral.mint(owner, 1000 * 1e6);
        uint256 value = 1000 * 1e6;
        uint256 deadline = block.timestamp + 1000;
        uint256 nonce = collateral.nonces(owner);
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(futuresMarket), value, nonce, deadline));
        bytes32 digest = collateral.hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        vm.prank(owner);
        futuresMarket.permit(address(collateral), value, deadline, v, r, s);

        assertEq(collateral.allowance(owner, address(futuresMarket)), value, "allowance mismatch");
    }

    function test_multicall_permitDepositMint() public {
        address debtToken = _open(_defaultConfig());

        address owner = vm.addr(1);
        uint128 value = 100_000 * 1e6;
        collateral.mint(owner, value);
        vm.startPrank(owner);
        bytes memory permitData;
        {
            uint256 deadline = block.timestamp + 1000;
            uint256 nonce = collateral.nonces(owner);
            bytes32 structHash = keccak256(
                abi.encode(
                    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                    owner,
                    address(futuresMarket),
                    uint256(value),
                    nonce,
                    deadline
                )
            );
            bytes32 digest = collateral.hashTypedDataV4(structHash);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

            permitData =
                abi.encodeWithSelector(futuresMarket.permit.selector, address(collateral), value, deadline, v, r, s);
        }

        // 2) deposit call
        bytes memory depositData = abi.encodeWithSelector(futuresMarket.deposit.selector, debtToken, owner, value);

        // 3) mint call
        bytes memory mintData = abi.encodeWithSelector(futuresMarket.mint.selector, debtToken, owner, 200 * 1e18);

        bytes[] memory calls = new bytes[](3);
        calls[0] = permitData;
        calls[1] = depositData;
        calls[2] = mintData;

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Deposit(debtToken, owner, owner, value);
        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Mint(debtToken, owner, owner, 200 * 1e18, 150 * 1e18);
        futuresMarket.multicall(calls);

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, owner);
        assertEq(collateralAmount, value, "collateral mismatch");
        assertEq(debtAmount, 200 * 1e18, "debt mismatch");
    }

    function test_multicall_burnWithdraw() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        bytes memory burnData = abi.encodeWithSelector(futuresMarket.burn.selector, debtToken, address(this), 80 * 1e18);
        bytes memory withdrawData =
            abi.encodeWithSelector(futuresMarket.withdraw.selector, debtToken, address(this), 30_000 * 1e6);

        bytes[] memory calls = new bytes[](2);
        calls[0] = burnData;
        calls[1] = withdrawData;

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Burn(debtToken, address(this), address(this), 80 * 1e18);
        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Withdraw(debtToken, address(this), address(this), 30_000 * 1e6);
        futuresMarket.multicall(calls);

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(collateralAmount, 70_000 * 1e6, "collateral mismatch");
        assertEq(debtAmount, 120 * 1e18, "debt mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 120 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(address(this)), 30_000 * 1e6, "collateral balance mismatch");
    }

    function test_multicall_updateOracleLiquidate() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        bytes memory updateData = abi.encodeWithSelector(
            futuresMarket.updateOracle.selector,
            abi.encode(DEBT_ASSET_ID, 800 * 1e18) // mock new price
        );

        bytes memory liquidateData =
            abi.encodeWithSelector(futuresMarket.liquidate.selector, debtToken, address(this), 140 * 1e18, true, "");

        bytes[] memory calls = new bytes[](2);
        calls[0] = updateData;
        calls[1] = liquidateData;

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Liquidate(debtToken, address(this), address(this), 140 * 1e18, 70_000 * 1e6, 400 * 1e18);
        futuresMarket.multicall{value: 0.001 ether}(calls);

        assertEq(oracle.getAssetPrice(DEBT_ASSET_ID), 800 * 1e18, "price mismatch");
        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(collateralAmount, 30_000 * 1e6, "collateral mismatch");
        assertEq(debtAmount, 60 * 1e18, "debt mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 60 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(address(this)), 70_000 * 1e6, "collateral balance mismatch");
    }

    function test_multicall_redeemClose() public {
        address debtToken = _open(_defaultConfig());
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(futuresMarket), 100_000 * 1e6);
        futuresMarket.deposit(debtToken, address(this), 100_000 * 1e6);
        futuresMarket.mint(debtToken, address(this), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 400 * 1e18));

        vm.warp(FUTURE_EXPIRATION + 1);
        futuresMarket.settle(debtToken);

        bytes memory redeemData = abi.encodeWithSelector(futuresMarket.redeem.selector, debtToken, RECEIVER, 200 * 1e18);
        bytes memory closeData = abi.encodeWithSelector(futuresMarket.close.selector, debtToken, address(this));

        bytes[] memory calls = new bytes[](2);
        calls[0] = redeemData;
        calls[1] = closeData;

        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Redeem(debtToken, address(this), RECEIVER, 200 * 1e18, 40_000 * 1e6);
        vm.expectEmit(address(futuresMarket));
        emit IMarketPosition.Close(debtToken, address(this), address(this), 60_000 * 1e6);
        futuresMarket.multicall(calls);

        (uint128 collateralAmount, uint128 debtAmount) = futuresMarket.getPosition(debtToken, address(this));
        assertEq(collateralAmount, 0, "collateral mismatch");
        assertEq(debtAmount, 0, "debt mismatch");
        assertEq(collateral.balanceOf(address(this)), 60_000 * 1e6, "collateral balance mismatch");
        assertEq(collateral.balanceOf(RECEIVER), 40_000 * 1e6, "collateral balance mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 0, "debt balance mismatch");
    }

    function test_supportsInterface() public view {
        assertTrue(futuresMarket.supportsInterface(type(IERC165).interfaceId));
        assertTrue(futuresMarket.supportsInterface(type(IDiamondCut).interfaceId));
        assertTrue(futuresMarket.supportsInterface(type(IDiamondLoupe).interfaceId));
        assertTrue(futuresMarket.supportsInterface(type(IERC3156FlashLender).interfaceId));
        assertTrue(futuresMarket.supportsInterface(0x7f5828d0)); // EIP173
    }

    function test_changeExpiration() public {
        address debtToken = _open(_defaultConfig());
        uint40 newExpiration = uint40(block.timestamp + 2 days);

        vm.expectEmit(address(futuresMarket));
        emit IMarketManager.ChangeExpiration(debtToken, newExpiration);

        futuresMarket.changeExpiration(debtToken, newExpiration);

        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        assertEq(market.expiration, newExpiration, "expiration mismatch");
    }

    function test_changeExpiration_invalidConfig() public {
        address debtToken = _open(_defaultConfig());
        uint40 invalidExpiration = uint40(block.timestamp - 1);

        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        futuresMarket.changeExpiration(debtToken, invalidExpiration);
    }

    function test_changeLtv() public {
        address debtToken = _open(_defaultConfig());
        uint24 newLtv = 400000; // 40%

        vm.expectEmit(address(futuresMarket));
        emit IMarketManager.ChangeLtv(debtToken, newLtv);

        futuresMarket.changeLtv(debtToken, newLtv);

        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        assertEq(market.ltv, newLtv, "ltv mismatch");
    }

    function test_changeLtv_invalidConfig() public {
        address debtToken = _open(_defaultConfig());

        // Test LTV > RATE_PRECISION
        uint24 invalidLtv = uint24(LibMarket.RATE_PRECISION) + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        futuresMarket.changeLtv(debtToken, invalidLtv);

        // Test LTV > liquidationThreshold
        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        futuresMarket.changeLtv(debtToken, market.liquidationThreshold + 1);
    }

    function test_changeLiquidationThreshold() public {
        address debtToken = _open(_defaultConfig());
        uint24 newThreshold = 800000; // 80%

        vm.expectEmit(address(futuresMarket));
        emit IMarketManager.ChangeLiquidationThreshold(debtToken, newThreshold);

        futuresMarket.changeLiquidationThreshold(debtToken, newThreshold);

        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        assertEq(market.liquidationThreshold, newThreshold, "liquidationThreshold mismatch");
    }

    function test_changeLiquidationThreshold_invalidConfig() public {
        address debtToken = _open(_defaultConfig());

        // Test threshold > RATE_PRECISION
        uint24 invalidThreshold = uint24(LibMarket.RATE_PRECISION) + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        futuresMarket.changeLiquidationThreshold(debtToken, invalidThreshold);

        // Test threshold < LTV
        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfig.selector));
        futuresMarket.changeLiquidationThreshold(debtToken, market.ltv - 1);
    }

    function test_changeMinDebt() public {
        address debtToken = _open(_defaultConfig());
        uint128 newMinDebt = 0.02 ether;

        vm.expectEmit(address(futuresMarket));
        emit IMarketManager.ChangeMinDebt(debtToken, newMinDebt);

        futuresMarket.changeMinDebt(debtToken, newMinDebt);

        IFuturesMarket.Market memory market = futuresMarket.getMarket(debtToken);
        assertEq(market.minDebt, newMinDebt, "minDebt mismatch");
    }

    function test_marketConfigChanges_afterSettlement() public {
        address debtToken = _open(_defaultConfig());

        // Settle the market
        vm.warp(FUTURE_EXPIRATION + 1);
        futuresMarket.settle(debtToken);

        // Try to change configurations after settlement
        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.changeExpiration(debtToken, uint40(block.timestamp + 1 days));

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.changeLtv(debtToken, 400000);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.changeLiquidationThreshold(debtToken, 800000);

        vm.expectRevert(abi.encodeWithSelector(AlreadySettled.selector));
        futuresMarket.changeMinDebt(debtToken, 0.02 ether);
    }

    function test_marketConfigChanges_onlyOwner() public {
        address debtToken = _open(_defaultConfig());
        address nonOwner = address(0xBEEF);

        vm.startPrank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        futuresMarket.changeExpiration(debtToken, uint40(block.timestamp + 1 days));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        futuresMarket.changeLtv(debtToken, 400000);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        futuresMarket.changeLiquidationThreshold(debtToken, 800000);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        futuresMarket.changeMinDebt(debtToken, 0.02 ether);

        vm.stopPrank();
    }

    function test_marketConfigChanges_nonExistentMarket() public {
        address nonExistentMarket = address(0x1234567890123456789012345678901234567890);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.changeExpiration(nonExistentMarket, uint40(block.timestamp + 1 days));

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.changeLtv(nonExistentMarket, 400000);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.changeLiquidationThreshold(nonExistentMarket, 800000);

        vm.expectRevert(abi.encodeWithSelector(MarketDoesNotExist.selector));
        futuresMarket.changeMinDebt(nonExistentMarket, 0.02 ether);
    }

    function test_extsload_single() public {
        // Store some value in storage
        bytes32 slot = keccak256("test.slot");
        bytes32 value = bytes32(uint256(123));
        vm.store(address(futuresMarket), slot, value);

        // Read using extsload
        bytes32 result = futuresMarket.extsload(slot);
        assertEq(result, value, "single slot value mismatch");
    }

    function test_extsload_multiple_sequential() public {
        // Store multiple sequential values
        bytes32 startSlot = keccak256("test.sequential.slot");
        uint256 nSlots = 3;
        
        bytes32[] memory expectedValues = new bytes32[](nSlots);
        for (uint256 i = 0; i < nSlots; i++) {
            bytes32 value = bytes32(uint256(i + 1));
            vm.store(address(futuresMarket), bytes32(uint256(startSlot) + i), value);
            expectedValues[i] = value;
        }

        // Read using sequential extsload
        bytes32[] memory results = futuresMarket.extsload(startSlot, nSlots);
        
        assertEq(results.length, nSlots, "number of slots mismatch");
        for (uint256 i = 0; i < nSlots; i++) {
            assertEq(results[i], expectedValues[i], "sequential slot value mismatch");
        }
    }

    function test_extsload_multiple_arbitrary() public {
        // Store values at arbitrary slots
        bytes32[] memory slots = new bytes32[](3);
        bytes32[] memory expectedValues = new bytes32[](3);
        
        for (uint256 i = 0; i < slots.length; i++) {
            slots[i] = keccak256(abi.encode("test.arbitrary.slot", i));
            expectedValues[i] = bytes32(uint256(i + 100));
            vm.store(address(futuresMarket), slots[i], expectedValues[i]);
        }

        // Read using arbitrary slots extsload
        bytes32[] memory results = futuresMarket.extsload(slots);
        
        assertEq(results.length, slots.length, "number of arbitrary slots mismatch");
        for (uint256 i = 0; i < slots.length; i++) {
            assertEq(results[i], expectedValues[i], "arbitrary slot value mismatch");
        }
    }
}
