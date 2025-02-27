// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {VaultManager, IVaultManager} from "../src/VaultManager.sol";
import {Debt} from "../src/Debt.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockLiquidator} from "./mocks/MockLiquidator.sol";

contract VaultManagerTest is Test {
    VaultManager public vaultManager;
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
        address impl = address(new VaultManager(address(oracle)));
        address vaultManagerProxy = address(new ERC1967Proxy(impl, ""));
        address debtTokenImpl = address(new Debt(vaultManagerProxy));

        vaultManager = VaultManager(vaultManagerProxy);
        vaultManager.initialize(address(this), debtTokenImpl);
        liquidator = new MockLiquidator(vaultManager);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 300 * 1e18)); // $300
        oracle.setAssetId(address(collateral), COLLATERAL_ASSET_ID);
        oracle.updatePrice(abi.encode(COLLATERAL_ASSET_ID, 2 * 1e18)); // $2
    }

    function _defaultConfig() internal view returns (IVaultManager.Config memory) {
        return IVaultManager.Config({
            assetId: DEBT_ASSET_ID,
            collateral: address(collateral),
            expiration: FUTURE_EXPIRATION,
            ltv: 500000,
            liquidationThreshold: 750000,
            minDebt: 0.01 ether,
            settlePrice: 0
        });
    }

    function test_open() public {
        IVaultManager.Config memory config = _defaultConfig();
        vm.expectEmit(false, false, false, true);
        emit IVaultManager.Open(address(0), config);

        address debtToken = vaultManager.open(config, "DebtToken", "DBT");
        assertTrue(debtToken != address(0));

        IVaultManager.Config memory stored = vaultManager.getConfig(debtToken);
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
        IVaultManager.Config memory cfg = _defaultConfig();

        cfg.ltv = 1e6 + 1;
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.InvalidConfig.selector));
        vaultManager.open(cfg, "DebtToken", "DBT");

        cfg = _defaultConfig();
        cfg.liquidationThreshold = 1e6 + 1;
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.InvalidConfig.selector));
        vaultManager.open(cfg, "DebtToken", "DBT");

        cfg = _defaultConfig();
        cfg.expiration = uint40(block.timestamp - 1);
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.InvalidConfig.selector));
        vaultManager.open(cfg, "DebtToken", "DBT");

        cfg = _defaultConfig();
        cfg.liquidationThreshold = cfg.ltv - 1;
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.InvalidConfig.selector));
        vaultManager.open(cfg, "DebtToken", "DBT");
    }

    function test_openDuplicate() public {
        vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        vm.expectRevert(abi.encodeWithSignature("FailedDeployment()"));
        vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
    }

    function test_openOwnership() public {
        IVaultManager.Config memory config = _defaultConfig();

        address nonOwner = address(0xBEEF);
        vm.startPrank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vaultManager.open(config, "DebtToken", "DBT");

        vm.stopPrank();
    }

    function test_deposit() public {
        IVaultManager.Config memory config = _defaultConfig();
        address debtToken = vaultManager.open(config, "DebtToken", "DBT");

        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Deposit(debtToken, address(this), RECEIVER, 50_000 * 1e6);

        vaultManager.deposit(debtToken, RECEIVER, 50_000 * 1e6);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, RECEIVER);
        assertEq(position.collateral, 50_000 * 1e6, "collateral mismatch");
        assertEq(position.debt, 0, "debt should remain 0");
        assertEq(collateral.balanceOf(address(vaultManager)), 50_000 * 1e6, "vaultManager collateral balance mismatch");
    }

    function test_withdraw() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Withdraw(debtToken, address(this), RECEIVER, 50_000 * 1e6);

        vaultManager.withdraw(debtToken, RECEIVER, 50_000 * 1e6);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.collateral, 50_000 * 1e6, "collateral mismatch after withdraw");
        assertEq(position.debt, 0, "debt mismatch after withdraw");
        assertEq(collateral.balanceOf(RECEIVER), 50_000 * 1e6, "receiver collateral balance mismatch");
    }

    function test_withdrawInvalidAmount() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.InsufficientCollateral.selector));
        vaultManager.withdraw(debtToken, address(this), 200_000 * 1e6);
    }

    function test_withdrawExceedsLtv() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        // Mint some debt so LTV is borderline
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        // Attempt to withdraw enough to exceed LTV
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.LTVExceeded.selector));
        vaultManager.withdraw(debtToken, address(this), 90_000 * 1e6);
    }

    function test_mint() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Mint(debtToken, address(this), RECEIVER, 200 * 1e18, 150 * 1e18);

        vaultManager.mint(debtToken, RECEIVER, 200 * 1e18);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.debt, 200 * 1e18, "debt mismatch after mint");
        assertEq(position.collateral, 100_000 * 1e6, "collateral mismatch after mint");
        assertEq(IERC20(debtToken).balanceOf(RECEIVER), 200 * 1e18, "receiver debt balance mismatch");
    }

    function test_mintExceedsLtv() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.LTVExceeded.selector));
        vaultManager.mint(debtToken, address(this), 400 * 1e18);
    }

    function test_burn() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vaultManager.mint(debtToken, RECEIVER, 100 * 1e18);

        // Expect burn event
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Burn(debtToken, RECEIVER, address(this), 80 * 1e18, 150 * 1e18);

        vm.prank(RECEIVER);
        vaultManager.burn(debtToken, address(this), 80 * 1e18);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.debt, 20 * 1e18, "debt mismatch after burn");
        assertEq(IERC20(debtToken).balanceOf(RECEIVER), 20 * 1e18, "debt balance mismatch after burn");
    }

    function test_burnExceedsDebt() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vaultManager.mint(debtToken, address(this), 40 * 1e18);

        // Attempt to burn more than minted
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.BurnExceedsDebt.selector));
        vaultManager.burn(debtToken, address(this), 100 * 1e18);
    }

    function test_burnAfterSettlement() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 40 * 1e18);

        // Move time forward to after expiration
        vm.warp(FUTURE_EXPIRATION + 1);

        // Settle the vault
        vaultManager.settle(debtToken);

        // Burn after settlement is allowed
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Burn(debtToken, address(this), address(this), 20 * 1e18, 150 * 1e18);
        vaultManager.burn(debtToken, address(this), 20 * 1e18);
    }

    function test_settle() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        vm.warp(FUTURE_EXPIRATION + 1); // move time forward

        uint256 expectedSettlePrice = 150 * 1e18;

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Settle(debtToken, expectedSettlePrice);

        uint256 settlePrice = vaultManager.settle(debtToken);
        // Check that isSettled is now true
        assertTrue(vaultManager.isSettled(debtToken), "Vault should be settled");
        assertEq(settlePrice, expectedSettlePrice, "settlePrice mismatch");

        // Check that returned settlePrice is stored
        IVaultManager.Config memory config = vaultManager.getConfig(debtToken);
        assertEq(config.settlePrice, settlePrice, "settlePrice mismatch");
    }

    function test_settleBeforeExpiration() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        // Don't warp to the future
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.NotExpired.selector));
        vaultManager.settle(debtToken);
    }

    function test_liquidate() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, LIQUIDATOR, 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 800 * 1e18));

        // Liquidator calls liquidate
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Liquidate(debtToken, LIQUIDATOR, address(this), 80 * 1e18, 40_000 * 1e6, 400 * 1e18);

        vm.startPrank(LIQUIDATOR);
        (uint128 debtCovered, uint128 collateralLiquidated) =
            vaultManager.liquidate(debtToken, address(this), 80 * 1e18, true, "");

        // Check the returned values
        assertEq(debtCovered, 80 * 1e18, "debtCovered mismatch");
        assertEq(collateralLiquidated, 40_000 * 1e6, "collateralLiquidated mismatch");

        // Check user's position now
        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.debt, 120 * 1e18, "Remaining debt mismatch");
        assertEq(position.collateral, 60_000 * 1e6, "Remaining collateral mismatch");
        assertEq(IERC20(debtToken).balanceOf(LIQUIDATOR), 120 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(LIQUIDATOR), 40_000 * 1e6, "collateral balance mismatch");
    }

    function test_liquidateSafePosition() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.PositionSafe.selector));
        vaultManager.liquidate(debtToken, address(this), 200 * 1e18, true, "");
    }

    function test_liquidateExceedsDebt() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, LIQUIDATOR, 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 800 * 1e18));

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Liquidate(debtToken, LIQUIDATOR, address(this), 200 * 1e18, 100_000 * 1e6, 400 * 1e18);

        vm.startPrank(LIQUIDATOR);
        (uint128 debtCovered, uint128 collateralLiquidated) =
            vaultManager.liquidate(debtToken, address(this), 240 * 1e18, true, "");
        assertEq(debtCovered, 200 * 1e18, "Should only cover up to actual debt");
        assertEq(collateralLiquidated, 100_000 * 1e6, "Should liquidate up to collateral");

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.debt, 0, "Remaining debt mismatch");
        assertEq(position.collateral, 0, "Remaining collateral mismatch");
        assertEq(IERC20(debtToken).balanceOf(LIQUIDATOR), 0, "debt balance mismatch");
        assertEq(collateral.balanceOf(LIQUIDATOR), 100_000 * 1e6, "collateral balance mismatch");
    }

    function test_liquidateWithInvalidCallback() public {
        // If liquidator != address(0) but doesn't implement onLiquidation
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        vm.expectRevert();
        vaultManager.liquidate(debtToken, address(this), 100 * 1e18, false, "0x");
    }

    function test_liquidateCallback() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(liquidator), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 800 * 1e18));

        bytes memory callbackData = abi.encode("test data");
        bytes32 expectedFlag =
            keccak256(abi.encode(debtToken, address(this), 120 * 1e18, 60_000 * 1e6, 400 * 1e18, callbackData));

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Liquidate(
            debtToken, address(liquidator), address(this), 120 * 1e18, 60_000 * 1e6, 400 * 1e18
        );

        (uint128 debtCovered, uint128 collateralLiquidated) =
            liquidator.liquidate(debtToken, address(this), 120 * 1e18, callbackData);

        assertEq(debtCovered, 120 * 1e18, "debtCovered mismatch");
        assertEq(collateralLiquidated, 60_000 * 1e6, "collateralLiquidated mismatch");
        assertEq(liquidator.flag(), expectedFlag, "liquidator flag mismatch");

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.debt, 80 * 1e18, "Remaining debt mismatch");
        assertEq(position.collateral, 40_000 * 1e6, "Remaining collateral mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(liquidator)), 80 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(address(liquidator)), 60_000 * 1e6, "collateral balance mismatch");
    }

    function test_redeem() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        // deposit + mint
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 400 * 1e18));

        // Advance time, settle
        vm.warp(FUTURE_EXPIRATION + 1);
        vaultManager.settle(debtToken);

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Redeem(debtToken, address(this), RECEIVER, 100 * 1e18, 20_000 * 1e6);

        uint128 collateralReceived = vaultManager.redeem(debtToken, RECEIVER, 100 * 1e18);
        assertEq(collateralReceived, 20_000 * 1e6, "collateralReceived mismatch (example value)");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 100 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(RECEIVER), 20_000 * 1e6, "collateral balance mismatch");

        // See it does not effect
        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 99999999 * 1e18));

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Redeem(debtToken, address(this), RECEIVER, 100 * 1e18, 20_000 * 1e6);

        collateralReceived = vaultManager.redeem(debtToken, RECEIVER, 100 * 1e18);
        assertEq(collateralReceived, 20_000 * 1e6, "collateralReceived mismatch (example value)");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 0, "debt balance mismatch");
        assertEq(collateral.balanceOf(RECEIVER), 40_000 * 1e6, "collateral balance mismatch");
    }

    function test_close() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 400 * 1e18));

        // Move time forward, settle
        vm.warp(FUTURE_EXPIRATION + 1);
        vaultManager.settle(debtToken);

        // If close() allows user to withdraw leftover collateral minus debt portion
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Close(debtToken, address(this), RECEIVER, 60_000 * 1e6);

        uint128 collateralReceived = vaultManager.close(debtToken, RECEIVER);
        assertEq(collateralReceived, 60_000 * 1e6, "collateralReceived mismatch");

        // Check that user's position is now zero
        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.collateral, 0, "Position collateral should be 0 after close");
        assertEq(position.debt, 0, "Position debt should be 0 after close");
        assertEq(collateral.balanceOf(RECEIVER), 60_000 * 1e6, "collateral balance mismatch");
    }

    function test_actionsWithInvalidId() public {
        address invalidAddress = address(0x1234567890123456789012345678901234567890);
        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.withdraw(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.deposit(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.mint(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.burn(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.liquidate(invalidAddress, address(this), 1, true, "");

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.redeem(invalidAddress, address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.VaultDoesNotExist.selector));
        vaultManager.close(invalidAddress, address(this));
    }

    function test_invalidActionsAfterSettlement() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);

        vm.warp(FUTURE_EXPIRATION + 1);
        vaultManager.settle(debtToken);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.AlreadySettled.selector));
        vaultManager.deposit(debtToken, address(this), 1_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.AlreadySettled.selector));
        vaultManager.withdraw(debtToken, address(this), 1_000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.AlreadySettled.selector));
        vaultManager.mint(debtToken, address(this), 10_000 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.AlreadySettled.selector));
        vaultManager.liquidate(debtToken, address(this), 10_000 * 1e18, true, "");
    }

    function test_invalidActionsBeforeSettlement() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.NotSettled.selector));
        vaultManager.redeem(debtToken, address(this), 10_000 * 1e18);

        vm.expectRevert(abi.encodeWithSelector(IVaultManager.NotSettled.selector));
        vaultManager.close(debtToken, address(this));
    }

    function test_updateOracle() public {
        bytes memory data = abi.encode(DEBT_ASSET_ID, 123456); // e.g. new price
        vaultManager.updateOracle(data);

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
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(vaultManager), value, nonce, deadline));
        bytes32 digest = collateral.hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        vm.prank(owner);
        vaultManager.permit(address(collateral), value, deadline, v, r, s);

        assertEq(collateral.allowance(owner, address(vaultManager)), value, "allowance mismatch");
    }

    function test_multicall_permitDepositMint() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");

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
                    address(vaultManager),
                    uint256(value),
                    nonce,
                    deadline
                )
            );
            bytes32 digest = collateral.hashTypedDataV4(structHash);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

            permitData =
                abi.encodeWithSelector(vaultManager.permit.selector, address(collateral), value, deadline, v, r, s);
        }

        // 2) deposit call
        bytes memory depositData = abi.encodeWithSelector(vaultManager.deposit.selector, debtToken, owner, value);

        // 3) mint call
        bytes memory mintData = abi.encodeWithSelector(vaultManager.mint.selector, debtToken, owner, 200 * 1e18);

        bytes[] memory calls = new bytes[](3);
        calls[0] = permitData;
        calls[1] = depositData;
        calls[2] = mintData;

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Deposit(debtToken, owner, owner, value);
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Mint(debtToken, owner, owner, 200 * 1e18, 150 * 1e18);
        vaultManager.multicall(calls);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, owner);
        assertEq(position.collateral, value, "collateral mismatch");
        assertEq(position.debt, 200 * 1e18, "debt mismatch");
    }

    function test_multicall_burnWithdraw() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        bytes memory burnData = abi.encodeWithSelector(vaultManager.burn.selector, debtToken, address(this), 80 * 1e18);
        bytes memory withdrawData =
            abi.encodeWithSelector(vaultManager.withdraw.selector, debtToken, address(this), 30_000 * 1e6);

        bytes[] memory calls = new bytes[](2);
        calls[0] = burnData;
        calls[1] = withdrawData;

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Burn(debtToken, address(this), address(this), 80 * 1e18, 150 * 1e18);
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Withdraw(debtToken, address(this), address(this), 30_000 * 1e6);
        vaultManager.multicall(calls);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.collateral, 70_000 * 1e6, "collateral mismatch");
        assertEq(position.debt, 120 * 1e18, "debt mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 120 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(address(this)), 30_000 * 1e6, "collateral balance mismatch");
    }

    function test_multicall_updateOracleLiquidate() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        bytes memory updateData = abi.encodeWithSelector(
            vaultManager.updateOracle.selector,
            abi.encode(DEBT_ASSET_ID, 800 * 1e18) // mock new price
        );

        bytes memory liquidateData =
            abi.encodeWithSelector(vaultManager.liquidate.selector, debtToken, address(this), 140 * 1e18, true, "");

        bytes[] memory calls = new bytes[](2);
        calls[0] = updateData;
        calls[1] = liquidateData;

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Liquidate(debtToken, address(this), address(this), 140 * 1e18, 70_000 * 1e6, 400 * 1e18);
        vaultManager.multicall(calls);

        assertEq(oracle.getAssetPrice(DEBT_ASSET_ID), 800 * 1e18, "price mismatch");
        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.collateral, 30_000 * 1e6, "collateral mismatch");
        assertEq(position.debt, 60 * 1e18, "debt mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 60 * 1e18, "debt balance mismatch");
        assertEq(collateral.balanceOf(address(this)), 70_000 * 1e6, "collateral balance mismatch");
    }

    function test_multicall_redeemClose() public {
        address debtToken = vaultManager.open(_defaultConfig(), "DebtToken", "DBT");
        collateral.mint(address(this), 100_000 * 1e6);
        collateral.approve(address(vaultManager), 100_000 * 1e6);
        vaultManager.deposit(debtToken, address(this), 100_000 * 1e6);
        vaultManager.mint(debtToken, address(this), 200 * 1e18);

        oracle.updatePrice(abi.encode(DEBT_ASSET_ID, 400 * 1e18));

        vm.warp(FUTURE_EXPIRATION + 1);
        vaultManager.settle(debtToken);

        bytes memory redeemData = abi.encodeWithSelector(vaultManager.redeem.selector, debtToken, RECEIVER, 200 * 1e18);
        bytes memory closeData = abi.encodeWithSelector(vaultManager.close.selector, debtToken, address(this));

        bytes[] memory calls = new bytes[](2);
        calls[0] = redeemData;
        calls[1] = closeData;

        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Redeem(debtToken, address(this), RECEIVER, 200 * 1e18, 40_000 * 1e6);
        vm.expectEmit(address(vaultManager));
        emit IVaultManager.Close(debtToken, address(this), address(this), 60_000 * 1e6);
        vaultManager.multicall(calls);

        IVaultManager.Position memory position = vaultManager.getPosition(debtToken, address(this));
        assertEq(position.collateral, 0, "collateral mismatch");
        assertEq(position.debt, 0, "debt mismatch");
        assertEq(collateral.balanceOf(address(this)), 60_000 * 1e6, "collateral balance mismatch");
        assertEq(collateral.balanceOf(RECEIVER), 40_000 * 1e6, "collateral balance mismatch");
        assertEq(IERC20(debtToken).balanceOf(address(this)), 0, "debt balance mismatch");
    }
}
