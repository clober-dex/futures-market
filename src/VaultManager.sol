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
    mapping(bytes32 => Config) internal _configs;
    mapping(bytes32 => mapping(address => Position)) internal _positions;

    constructor(address _priceOracle) {
        priceOracle = _priceOracle;
        pricePrecision = 10 ** IOracle(priceOracle).decimals();
    }

    function initialize(address _owner, address _debtTokenImplementation) external initializer {
        __Ownable_init(_owner);
        debtTokenImplementation = _debtTokenImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function encodeId(bytes32 assetId, address collateral, uint40 expiration) public pure returns (bytes32) {
        return keccak256(abi.encode(assetId, collateral, expiration));
    }

    function getConfig(bytes32 id) external view returns (Config memory) {
        return _configs[id];
    }

    function getPosition(bytes32 id, address user) external view returns (Position memory position) {
        return _positions[id][user];
    }

    function isSettled(bytes32 id) public view returns (bool) {
        return _configs[id].settlePrice > 0;
    }

    function getDebtToken(bytes32 id) public view returns (address) {
        return Clones.predictDeterministicAddress(debtTokenImplementation, id);
    }

    function open(Config calldata config, string calldata name, string calldata symbol)
        external
        nonReentrant
        onlyOwner
        returns (bytes32 id, address debtToken)
    {
        id = encodeId(config.assetId, config.collateral, config.expiration);
        if (_configs[id].assetId != bytes32(0)) revert VaultAlreadyExists();
        if (config.expiration < block.timestamp) revert InvalidConfig();
        if (config.ltv > config.liquidationThreshold) revert InvalidConfig();
        if (config.ltv > PRECISION) revert InvalidConfig();
        if (config.liquidationThreshold > PRECISION) revert InvalidConfig();

        debtToken = Clones.cloneDeterministic(debtTokenImplementation, id);
        Debt(debtToken).initialize(name, symbol);

        _configs[id] = config;
        emit Open(id, debtToken, config);
    }

    function _getRelativePrice(bytes32 id) internal view returns (uint256) {
        Config storage config = _configs[id];
        uint256 collateralPrice = IOracle(priceOracle).getAssetPrice(config.collateral);
        uint256 debtPrice = IOracle(priceOracle).getAssetPrice(config.assetId);
        return debtPrice * pricePrecision / collateralPrice;
    }

    function _isUnderLtv(bytes32 id, address user, uint256 relativePrice) internal view returns (bool) {
        Config storage config = _configs[id];
        Position memory position = _positions[id][user];
        return uint256(position.collateral) * config.ltv * pricePrecision
            > uint256(position.debt) * relativePrice * PRECISION;
    }

    function _isPositionSafe(bytes32 id, address user, uint256 relativePrice) internal view returns (bool) {
        Config storage config = _configs[id];
        Position memory position = _positions[id][user];
        return uint256(position.collateral) * config.liquidationThreshold * pricePrecision
            > uint256(position.debt) * relativePrice * PRECISION;
    }

    function deposit(bytes32 id, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(id)) revert AlreadySettled();

        IERC20(config.collateral).safeTransferFrom(msg.sender, address(this), amount);
        _positions[id][to].collateral += amount;
        emit Deposit(id, msg.sender, to, amount);
    }

    function withdraw(bytes32 id, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(id)) revert AlreadySettled();

        Position memory position = _positions[id][msg.sender];
        if (position.collateral < amount) revert InsufficientCollateral();
        unchecked {
            _positions[id][msg.sender].collateral = position.collateral - amount;
        }
        uint256 relativePrice = _getRelativePrice(id);
        if (!_isUnderLtv(id, msg.sender, relativePrice)) revert LTVExceeded();

        IERC20(config.collateral).safeTransfer(to, amount);
        emit Withdraw(id, msg.sender, to, amount);
    }

    function mint(bytes32 id, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(id)) revert AlreadySettled();

        _positions[id][msg.sender].debt += amount;
        uint256 relativePrice = _getRelativePrice(id);
        if (!_isUnderLtv(id, msg.sender, relativePrice)) revert LTVExceeded();

        Debt(getDebtToken(id)).mint(to, amount);
        emit Mint(id, msg.sender, to, amount, relativePrice);
    }

    function burn(bytes32 id, address to, uint128 amount) external nonReentrant {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();

        Position memory position = _positions[id][to];
        if (position.debt < amount) revert BurnExceedsDebt();

        Debt(getDebtToken(id)).burn(msg.sender, amount);
        unchecked {
            _positions[id][to].debt = position.debt - amount;
        }
        emit Burn(id, msg.sender, to, amount, _getRelativePrice(id));
    }

    function settle(bytes32 id) external nonReentrant returns (uint256 settlePrice) {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(id)) revert AlreadySettled();
        if (block.timestamp < config.expiration) revert NotExpired();

        settlePrice = _getRelativePrice(id);
        _configs[id].settlePrice = settlePrice;
        emit Settle(id, settlePrice);
    }

    function liquidate(bytes32 id, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        nonReentrant
        returns (uint128 debtCovered, uint128 collateralLiquidated)
    {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(id)) revert AlreadySettled();
        uint256 relativePrice = _getRelativePrice(id);
        if (_isPositionSafe(id, user, relativePrice)) revert PositionSafe();

        Position memory position = _positions[id][user];
        if (position.debt < debtToCover) {
            debtCovered = position.debt;
            collateralLiquidated = position.collateral;
        } else {
            debtCovered = debtToCover;
            collateralLiquidated = uint128(uint256(position.collateral) * debtCovered / position.debt);
        }
        unchecked {
            _positions[id][user].debt = position.debt - debtCovered;
            _positions[id][user].collateral = position.collateral - collateralLiquidated;
        }

        IERC20(config.collateral).safeTransfer(msg.sender, collateralLiquidated);
        if (!skipCallback) {
            // todo: separate caller and liquidator
            ILiquidator(msg.sender).onLiquidation(
                id, msg.sender, user, debtCovered, collateralLiquidated, relativePrice, data
            );
        }
        Debt(getDebtToken(id)).burn(msg.sender, debtCovered);

        emit Liquidate(id, msg.sender, user, debtCovered, collateralLiquidated, relativePrice);
    }

    function redeem(bytes32 id, address to, uint128 amount)
        external
        nonReentrant
        returns (uint128 collateralReceived)
    {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (!isSettled(id)) revert NotSettled();

        Debt(getDebtToken(id)).burn(msg.sender, amount);

        collateralReceived = uint128(uint256(amount) * config.settlePrice / pricePrecision);
        IERC20(config.collateral).safeTransfer(to, collateralReceived);
        emit Redeem(id, msg.sender, to, amount, collateralReceived);
    }

    function close(bytes32 id, address to) external nonReentrant returns (uint128 collateralReceived) {
        Config storage config = _configs[id];
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (!isSettled(id)) revert NotSettled();

        Position memory position = _positions[id][msg.sender];
        collateralReceived = position.collateral - uint128(uint256(position.debt) * config.settlePrice / pricePrecision);
        IERC20(config.collateral).safeTransfer(to, collateralReceived);
        delete _positions[id][msg.sender];

        emit Close(id, msg.sender, to, collateralReceived);
    }

    function updateOracle(bytes32 assetId, bytes calldata data) external payable returns (uint256) {
        // todo: receive fee amount
        return IOracle(priceOracle).updatePrice{value: msg.value}(assetId, data);
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
