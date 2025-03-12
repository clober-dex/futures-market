// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {ICreateX} from "../interfaces/ICreateX.sol";
import {IDiamond} from "../interfaces/IDiamond.sol";
import {IMarketManager} from "../interfaces/IMarketManager.sol";
import {IMarketPosition} from "../interfaces/IMarketPosition.sol";
import {IMarketView} from "../interfaces/IMarketView.sol";
import {IOwnership} from "../interfaces/IOwnership.sol";
import {IUtils} from "../interfaces/IUtils.sol";
import {FlashLoanFacet} from "../facets/FlashLoanFacet.sol";
import {MarketManagerFacet} from "../facets/MarketManagerFacet.sol";
import {MarketPositionFacet} from "../facets/MarketPositionFacet.sol";
import {MarketViewFacet} from "../facets/MarketViewFacet.sol";
import {OwnershipFacet} from "../facets/OwnershipFacet.sol";
import {UtilsFacet} from "../facets/UtilsFacet.sol";
import {CREATEX_ADDRESS} from "./CreateX.sol";

type Deployer is address;

library FacetDeployer {
    function create3(Deployer deployer, bytes32 salt, bytes memory initCode) internal returns (address deployed) {
        bytes32 guardedSalt = keccak256(abi.encodePacked(uint256(uint160(Deployer.unwrap(deployer))), salt));
        address computedAddress = ICreateX(CREATEX_ADDRESS).computeCreate3Address(guardedSalt, CREATEX_ADDRESS);
        if (computedAddress.codehash != bytes32(0)) {
            revert("Address already deployed");
        }

        deployed = ICreateX(CREATEX_ADDRESS).deployCreate3(salt, initCode);
        require(computedAddress == deployed, "Address does not match");
    }

    function create2(Deployer deployer, bytes memory initCode) internal returns (address deployed) {
        bytes32 salt = bytes32(abi.encodePacked(Deployer.unwrap(deployer), hex"00", bytes11(0)));

        bytes32 guardedSalt = keccak256(abi.encodePacked(uint256(uint160(Deployer.unwrap(deployer))), salt));
        address computedAddress = ICreateX(CREATEX_ADDRESS).computeCreate2Address(guardedSalt, keccak256(initCode));
        if (computedAddress.codehash != bytes32(0)) {
            return computedAddress;
        }

        deployed = ICreateX(CREATEX_ADDRESS).deployCreate2(salt, initCode);
        require(computedAddress == deployed, "Address does not match");
    }

    function getFlashLoanFacetSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory functionSelectors = new bytes4[](3);
        functionSelectors[0] = IERC3156FlashLender.maxFlashLoan.selector;
        functionSelectors[1] = IERC3156FlashLender.flashFee.selector;
        functionSelectors[2] = IERC3156FlashLender.flashLoan.selector;
        return functionSelectors;
    }

    function getMarketManagerFacetSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = IMarketManager.open.selector;
        functionSelectors[1] = IMarketManager.settle.selector;
        functionSelectors[2] = IMarketManager.updateOracle.selector;
        functionSelectors[3] = IMarketManager.changeExpiration.selector;
        functionSelectors[4] = IMarketManager.changeLtv.selector;
        functionSelectors[5] = IMarketManager.changeLiquidationThreshold.selector;
        functionSelectors[6] = IMarketManager.changeMinDebt.selector;
        return functionSelectors;
    }

    function getMarketPositionFacetSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = IMarketPosition.deposit.selector;
        functionSelectors[1] = IMarketPosition.withdraw.selector;
        functionSelectors[2] = IMarketPosition.mint.selector;
        functionSelectors[3] = IMarketPosition.burn.selector;
        functionSelectors[4] = IMarketPosition.liquidate.selector;
        functionSelectors[5] = IMarketPosition.redeem.selector;
        functionSelectors[6] = IMarketPosition.close.selector;
        return functionSelectors;
    }

    function getMarketViewFacetSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory functionSelectors = new bytes4[](3);
        functionSelectors[0] = IMarketView.getMarket.selector;
        functionSelectors[1] = IMarketView.getPosition.selector;
        functionSelectors[2] = IMarketView.isSettled.selector;
        return functionSelectors;
    }

    function getOwnershipFacetSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory functionSelectors = new bytes4[](5);
        functionSelectors[0] = IOwnership.owner.selector;
        functionSelectors[1] = IOwnership.pendingOwner.selector;
        functionSelectors[2] = IOwnership.renounceOwnership.selector;
        functionSelectors[3] = IOwnership.transferOwnership.selector;
        functionSelectors[4] = IOwnership.acceptOwnership.selector;
        return functionSelectors;
    }

    function getUtilsFacetSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = IUtils.permit.selector;
        functionSelectors[1] = IUtils.multicall.selector;
        functionSelectors[2] = 0x1e2eaeaf; // extsload(bytes32)
        functionSelectors[3] = 0x35fd631a; // extsload(bytes32,uint256)
        functionSelectors[4] = 0xdbd035ff; // extsload(bytes32[])
        functionSelectors[5] = 0xf135baaa; // exttload(bytes32)
        functionSelectors[6] = 0x9bf6645f; // exttload(bytes32[])
        return functionSelectors;
    }

    function getFlashLoanFacetInitCode() internal pure returns (bytes memory) {
        return type(FlashLoanFacet).creationCode;
    }

    function getMarketManagerFacetInitCode(address oracle, address debtTokenImpl)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(type(MarketManagerFacet).creationCode, abi.encode(oracle, debtTokenImpl));
    }

    function getMarketPositionFacetInitCode(address oracle) internal pure returns (bytes memory) {
        return abi.encodePacked(type(MarketPositionFacet).creationCode, abi.encode(oracle));
    }

    function getMarketViewFacetInitCode() internal pure returns (bytes memory) {
        return type(MarketViewFacet).creationCode;
    }

    function getOwnershipFacetInitCode() internal pure returns (bytes memory) {
        return type(OwnershipFacet).creationCode;
    }

    function getUtilsFacetInitCode() internal pure returns (bytes memory) {
        return type(UtilsFacet).creationCode;
    }

    function deployFlashLoanFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address flashLoanFacet = create2(deployer, getFlashLoanFacetInitCode());
        return IDiamond.FacetCut({
            facetAddress: flashLoanFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getFlashLoanFacetSelectors()
        });
    }

    function deployMarketManagerFacet(Deployer deployer, address oracle, address debtTokenImpl)
        internal
        returns (IDiamond.FacetCut memory)
    {
        address marketManagerFacet = create2(deployer, getMarketManagerFacetInitCode(oracle, debtTokenImpl));

        return IDiamond.FacetCut({
            facetAddress: marketManagerFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getMarketManagerFacetSelectors()
        });
    }

    function deployMarketPositionFacet(Deployer deployer, address oracle) internal returns (IDiamond.FacetCut memory) {
        address marketPositionFacet = create2(deployer, getMarketPositionFacetInitCode(oracle));

        return IDiamond.FacetCut({
            facetAddress: marketPositionFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getMarketPositionFacetSelectors()
        });
    }

    function deployMarketViewFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address marketViewFacet = create2(deployer, getMarketViewFacetInitCode());

        return IDiamond.FacetCut({
            facetAddress: marketViewFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getMarketViewFacetSelectors()
        });
    }

    function deployOwnershipFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address ownershipFacet = create2(deployer, getOwnershipFacetInitCode());

        return IDiamond.FacetCut({
            facetAddress: ownershipFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getOwnershipFacetSelectors()
        });
    }

    function deployUtilsFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address utilsFacet = create2(deployer, getUtilsFacetInitCode());

        return IDiamond.FacetCut({
            facetAddress: utilsFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getUtilsFacetSelectors()
        });
    }
}
