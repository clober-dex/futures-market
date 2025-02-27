// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC3156FlashLender, IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {IVaultManager} from "./interfaces/IVaultManager.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ILiquidator} from "./interfaces/ILiquidator.sol";
import {Debt} from "./Debt.sol";

contract VaultManager is
    IVaultManager,
    IERC3156FlashLender,
    ERC165,
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    MulticallUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 internal constant PRECISION = 1e6;
    bytes32 internal constant CALLBACK_MAGIC_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");
    address public immutable priceOracle;
    uint256 public immutable pricePrecision;

    address public debtTokenImplementation;
    mapping(address debtToken => Config) internal _configs;
    mapping(address debtToken => mapping(address user => Position)) internal _positions;

    constructor(address _priceOracle) {
        priceOracle = _priceOracle;
        pricePrecision = 10 ** IOracle(priceOracle).decimals();
    }

    function initialize(address _owner, address _debtTokenImplementation) external initializer {
        __Ownable_init(_owner);
        debtTokenImplementation = _debtTokenImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function predictDebtToken(bytes32 assetId, address collateral, uint40 expiration) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(assetId, collateral, expiration));
        return Clones.predictDeterministicAddress(debtTokenImplementation, salt);
    }

    function getConfig(address debtToken) external view returns (Config memory) {
        return _configs[debtToken];
    }

    function getPosition(address debtToken, address user) external view returns (Position memory) {
        return _positions[debtToken][user];
    }

    function isSettled(address debtToken) public view returns (bool) {
        return _configs[debtToken].settlePrice > 0;
    }

    function open(Config calldata config, string calldata name, string calldata symbol)
        external
        nonReentrant
        onlyOwner
        returns (address debtToken)
    {
        if (config.expiration < block.timestamp) revert InvalidConfig();
        if (config.ltv > config.liquidationThreshold) revert InvalidConfig();
        if (config.ltv > PRECISION) revert InvalidConfig();
        if (config.liquidationThreshold > PRECISION) revert InvalidConfig();

        bytes32 salt = keccak256(abi.encode(config.assetId, config.collateral, config.expiration));
        debtToken = Clones.cloneDeterministic(debtTokenImplementation, salt);
        Debt(debtToken).initialize(name, symbol);

        _configs[debtToken] = config;
        emit Open(debtToken, config);
    }

    function _getRelativePrice(address debtToken) internal view returns (uint256) {
        Config storage config = _configs[debtToken];
        uint256 collateralPrice = IOracle(priceOracle).getAssetPrice(config.collateral);
        uint256 debtPrice = IOracle(priceOracle).getAssetPrice(config.assetId);
        return debtPrice * pricePrecision / collateralPrice;
    }

    function _isUnderLtv(address debtToken, address user, uint256 relativePrice) internal view returns (bool) {
        Config storage config = _configs[debtToken];
        Position memory position = _positions[debtToken][user];
        return uint256(position.collateral) * config.ltv * pricePrecision
            > uint256(position.debt) * relativePrice * PRECISION;
    }

    function _isPositionSafe(address debtToken, address user, uint256 relativePrice) internal view returns (bool) {
        Config storage config = _configs[debtToken];
        Position memory position = _positions[debtToken][user];
        return uint256(position.collateral) * config.liquidationThreshold * pricePrecision
            > uint256(position.debt) * relativePrice * PRECISION;
    }

    function deposit(address debtToken, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(debtToken)) revert AlreadySettled();

        IERC20(config.collateral).safeTransferFrom(msg.sender, address(this), amount);
        _positions[debtToken][to].collateral += amount;
        emit Deposit(debtToken, msg.sender, to, amount);
    }

    function withdraw(address debtToken, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(debtToken)) revert AlreadySettled();

        Position memory position = _positions[debtToken][msg.sender];
        if (position.collateral < amount) revert InsufficientCollateral();
        unchecked {
            _positions[debtToken][msg.sender].collateral = position.collateral - amount;
        }
        uint256 relativePrice = _getRelativePrice(debtToken);
        if (!_isUnderLtv(debtToken, msg.sender, relativePrice)) revert LTVExceeded();

        IERC20(config.collateral).safeTransfer(to, amount);
        emit Withdraw(debtToken, msg.sender, to, amount);
    }

    function mint(address debtToken, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(debtToken)) revert AlreadySettled();

        _positions[debtToken][msg.sender].debt += amount;
        uint256 relativePrice = _getRelativePrice(debtToken);
        if (!_isUnderLtv(debtToken, msg.sender, relativePrice)) revert LTVExceeded();

        Debt(debtToken).mint(to, amount);
        emit Mint(debtToken, msg.sender, to, amount, relativePrice);
    }

    function burn(address debtToken, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();

        Position memory position = _positions[debtToken][to];
        if (position.debt < amount) revert BurnExceedsDebt();

        Debt(debtToken).burn(msg.sender, amount);
        unchecked {
            _positions[debtToken][to].debt = position.debt - amount;
        }
        emit Burn(debtToken, msg.sender, to, amount, _getRelativePrice(debtToken));
    }

    function settle(address debtToken) external nonReentrant returns (uint256 settlePrice) {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(debtToken)) revert AlreadySettled();
        if (block.timestamp < config.expiration) revert NotExpired();

        settlePrice = _getRelativePrice(debtToken);
        _configs[debtToken].settlePrice = settlePrice;
        emit Settle(debtToken, settlePrice);
    }

    function liquidate(address debtToken, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        nonReentrant
        returns (uint128 debtCovered, uint128 collateralLiquidated)
    {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(debtToken)) revert AlreadySettled();
        uint256 relativePrice = _getRelativePrice(debtToken);
        if (_isPositionSafe(debtToken, user, relativePrice)) revert PositionSafe();

        Position memory position = _positions[debtToken][user];
        if (position.debt < debtToCover) {
            debtCovered = position.debt;
            collateralLiquidated = position.collateral;
        } else {
            debtCovered = debtToCover;
            collateralLiquidated = uint128(uint256(position.collateral) * debtCovered / position.debt);
        }
        unchecked {
            _positions[debtToken][user].debt = position.debt - debtCovered;
            _positions[debtToken][user].collateral = position.collateral - collateralLiquidated;
        }

        IERC20(config.collateral).safeTransfer(msg.sender, collateralLiquidated);
        if (!skipCallback) {
            // todo: separate caller and liquidator
            ILiquidator(msg.sender).onLiquidation(
                debtToken, msg.sender, user, debtCovered, collateralLiquidated, relativePrice, data
            );
        }
        Debt(debtToken).burn(msg.sender, debtCovered);

        emit Liquidate(debtToken, msg.sender, user, debtCovered, collateralLiquidated, relativePrice);
    }

    function redeem(address debtToken, address to, uint128 amount)
        external
        nonReentrant
        returns (uint128 collateralReceived)
    {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (!isSettled(debtToken)) revert NotSettled();

        Debt(debtToken).burn(msg.sender, amount);

        collateralReceived = uint128(uint256(amount) * config.settlePrice / pricePrecision);
        IERC20(config.collateral).safeTransfer(to, collateralReceived);
        emit Redeem(debtToken, msg.sender, to, amount, collateralReceived);
    }

    function close(address debtToken, address to) external nonReentrant returns (uint128 collateralReceived) {
        Config storage config = _configs[debtToken];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (!isSettled(debtToken)) revert NotSettled();

        Position memory position = _positions[debtToken][msg.sender];
        collateralReceived = position.collateral - uint128(uint256(position.debt) * config.settlePrice / pricePrecision);
        IERC20(config.collateral).safeTransfer(to, collateralReceived);
        delete _positions[debtToken][msg.sender];

        emit Close(debtToken, msg.sender, to, collateralReceived);
    }

    function updateOracle(bytes calldata data) external payable {
        IOracle(priceOracle).updatePrice{value: msg.value}(data);
    }

    function permit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function maxFlashLoan(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function flashFee(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        nonReentrant
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
