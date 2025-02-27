// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
    uint256 internal immutable _pricePrecision;

    address public debtTokenImplementation;
    mapping(address debtToken => Config) internal _configs;
    mapping(address debtToken => mapping(address user => Position)) internal _positions;

    constructor(address _priceOracle) {
        priceOracle = _priceOracle;
        _pricePrecision = 10 ** IOracle(priceOracle).decimals();
    }

    function initialize(address _owner, address _debtTokenImplementation) external initializer {
        __Ownable_init(_owner);
        debtTokenImplementation = _debtTokenImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    function _transferToken(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _transferToken(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function _getRelativePrice(address debtToken) internal view returns (uint256) {
        Config storage config = _configs[debtToken];
        uint256 collateralPrice = IOracle(priceOracle).getAssetPrice(config.collateral);
        uint256 debtPrice = IOracle(priceOracle).getAssetPrice(config.assetId);
        return debtPrice * _pricePrecision / collateralPrice;
    }

    function _isUnderRatio(address collateral, address debtToken, address user, uint256 relativePrice, uint256 ratio)
        internal
        view
        returns (bool)
    {
        uint256 collateralPrecision = 10 ** IERC20Metadata(collateral).decimals();
        Position memory position = _positions[debtToken][user];
        return uint256(position.collateral) * ratio * _pricePrecision * 1e18
            > uint256(position.debt) * relativePrice * PRECISION * collateralPrecision;
    }

    function _isUnderLtv(address debtToken, address user, uint256 relativePrice) internal view returns (bool) {
        Config storage config = _configs[debtToken];
        return _isUnderRatio(config.collateral, debtToken, user, relativePrice, config.ltv);
    }

    function _isPositionSafe(address debtToken, address user, uint256 relativePrice) internal view returns (bool) {
        Config storage config = _configs[debtToken];
        return _isUnderRatio(config.collateral, debtToken, user, relativePrice, config.liquidationThreshold);
    }

    function _checkUnsettled(address debtToken) internal view {
        if (_configs[debtToken].assetId == bytes32(0)) revert VaultDoesNotExist();
        if (isSettled(debtToken)) revert AlreadySettled();
    }

    function deposit(address debtToken, address to, uint128 amount) external nonReentrant {
        _checkUnsettled(debtToken);

        _transferToken(_configs[debtToken].collateral, msg.sender, address(this), amount);
        _positions[debtToken][to].collateral += amount;
        emit Deposit(debtToken, msg.sender, to, amount);
    }

    function withdraw(address debtToken, address to, uint128 amount) external nonReentrant {
        _checkUnsettled(debtToken);

        Position memory position = _positions[debtToken][msg.sender];
        if (position.collateral < amount) revert InsufficientCollateral();
        unchecked {
            _positions[debtToken][msg.sender].collateral = position.collateral - amount;
        }
        uint256 relativePrice = _getRelativePrice(debtToken);
        if (!_isUnderLtv(debtToken, msg.sender, relativePrice)) revert LTVExceeded();

        _transferToken(_configs[debtToken].collateral, to, amount);
        emit Withdraw(debtToken, msg.sender, to, amount);
    }

    function mint(address debtToken, address to, uint128 amount) external nonReentrant {
        _checkUnsettled(debtToken);

        _positions[debtToken][msg.sender].debt += amount;
        uint256 relativePrice = _getRelativePrice(debtToken);
        if (!_isUnderLtv(debtToken, msg.sender, relativePrice)) revert LTVExceeded();

        Debt(debtToken).mint(to, amount);
        emit Mint(debtToken, msg.sender, to, amount, relativePrice);
    }

    function burn(address debtToken, address to, uint128 amount) external nonReentrant {
        _checkUnsettled(debtToken);

        Position memory position = _positions[debtToken][to];
        if (position.debt < amount) revert BurnExceedsDebt();

        Debt(debtToken).burn(msg.sender, amount);
        unchecked {
            _positions[debtToken][to].debt = position.debt - amount;
        }
        emit Burn(debtToken, msg.sender, to, amount, _getRelativePrice(debtToken));
    }

    function settle(address debtToken) external nonReentrant returns (uint256 settlePrice) {
        _checkUnsettled(debtToken);
        if (block.timestamp < _configs[debtToken].expiration) revert NotExpired();

        settlePrice = _getRelativePrice(debtToken);
        _configs[debtToken].settlePrice = settlePrice;
        emit Settle(debtToken, settlePrice);
    }

    function liquidate(address debtToken, address user, uint128 debtToCover, bool skipCallback, bytes calldata data)
        external
        nonReentrant
        returns (uint128 debtCovered, uint128 collateralLiquidated)
    {
        _checkUnsettled(debtToken);
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

        _transferToken(_configs[debtToken].collateral, msg.sender, collateralLiquidated);
        if (!skipCallback) {
            ILiquidator(msg.sender).onLiquidation(
                debtToken, user, debtCovered, collateralLiquidated, relativePrice, data
            );
        }
        Debt(debtToken).burn(msg.sender, debtCovered);

        emit Liquidate(debtToken, msg.sender, user, debtCovered, collateralLiquidated, relativePrice);
    }

    function _checkSettled(Config storage config, address debtToken) internal view {
        if (config.assetId == bytes32(0)) revert VaultDoesNotExist();
        if (!isSettled(debtToken)) revert NotSettled();
    }

    function _calculateSettledCollateral(Config storage config, uint128 amount) internal view returns (uint128) {
        uint256 collateralPrecision = 10 ** IERC20Metadata(config.collateral).decimals();
        return uint128(uint256(amount) * config.settlePrice * collateralPrecision / _pricePrecision / 1e18);
    }

    function redeem(address debtToken, address to, uint128 amount)
        external
        nonReentrant
        returns (uint128 collateralReceived)
    {
        Config storage config = _configs[debtToken];
        _checkSettled(config, debtToken);

        Debt(debtToken).burn(msg.sender, amount);

        collateralReceived = _calculateSettledCollateral(config, amount);
        _transferToken(config.collateral, to, collateralReceived);
        emit Redeem(debtToken, msg.sender, to, amount, collateralReceived);
    }

    function close(address debtToken, address to) external nonReentrant returns (uint128 collateralReceived) {
        Config storage config = _configs[debtToken];
        _checkSettled(config, debtToken);

        Position memory position = _positions[debtToken][msg.sender];

        unchecked {
            collateralReceived = position.collateral - _calculateSettledCollateral(config, position.debt);
        }

        _transferToken(config.collateral, to, collateralReceived);
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
        _transferToken(token, address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, 0, data) != CALLBACK_MAGIC_VALUE) {
            revert InvalidFlashLoanCallback();
        }
        _transferToken(token, address(receiver), address(this), amount);
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC3156FlashLender).interfaceId || super.supportsInterface(interfaceId);
    }
}
