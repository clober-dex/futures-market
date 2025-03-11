// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

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

    function deployFlashLoanFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address flashLoanFacet = create2(deployer, type(FlashLoanFacet).creationCode);

        bytes4[] memory functionSelectors = new bytes4[](3);
        functionSelectors[0] = IERC3156FlashLender.maxFlashLoan.selector;
        functionSelectors[1] = IERC3156FlashLender.flashFee.selector;
        functionSelectors[2] = IERC3156FlashLender.flashLoan.selector;

        return IDiamond.FacetCut({
            facetAddress: flashLoanFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }

    function deployMarketManagerFacet(Deployer deployer, address oracle, address debtTokenImpl)
        internal
        returns (IDiamond.FacetCut memory)
    {
        bytes memory initCode =
            abi.encodePacked(type(MarketManagerFacet).creationCode, abi.encode(oracle, debtTokenImpl));

        address marketManagerFacet = create2(deployer, initCode);

        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = IMarketManager.open.selector;
        functionSelectors[1] = IMarketManager.settle.selector;
        functionSelectors[2] = IMarketManager.updateOracle.selector;
        functionSelectors[3] = IMarketManager.changeExpiration.selector;
        functionSelectors[4] = IMarketManager.changeLtv.selector;
        functionSelectors[5] = IMarketManager.changeLiquidationThreshold.selector;
        functionSelectors[6] = IMarketManager.changeMinDebt.selector;

        return IDiamond.FacetCut({
            facetAddress: marketManagerFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }

    function deployMarketPositionFacet(Deployer deployer, address oracle) internal returns (IDiamond.FacetCut memory) {
        bytes memory initCode = abi.encodePacked(type(MarketPositionFacet).creationCode, abi.encode(oracle));

        address marketPositionFacet = create2(deployer, initCode);

        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = IMarketPosition.deposit.selector;
        functionSelectors[1] = IMarketPosition.withdraw.selector;
        functionSelectors[2] = IMarketPosition.mint.selector;
        functionSelectors[3] = IMarketPosition.burn.selector;
        functionSelectors[4] = IMarketPosition.liquidate.selector;
        functionSelectors[5] = IMarketPosition.redeem.selector;
        functionSelectors[6] = IMarketPosition.close.selector;

        return IDiamond.FacetCut({
            facetAddress: marketPositionFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }

    function deployMarketViewFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address marketViewFacet = create2(deployer, type(MarketViewFacet).creationCode);

        bytes4[] memory functionSelectors = new bytes4[](3);
        functionSelectors[0] = IMarketView.getMarket.selector;
        functionSelectors[1] = IMarketView.getPosition.selector;
        functionSelectors[2] = IMarketView.isSettled.selector;

        return IDiamond.FacetCut({
            facetAddress: marketViewFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }

    function deployOwnershipFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address ownershipFacet = create2(deployer, type(OwnershipFacet).creationCode);

        bytes4[] memory functionSelectors = new bytes4[](5);
        functionSelectors[0] = IOwnership.owner.selector;
        functionSelectors[1] = IOwnership.pendingOwner.selector;
        functionSelectors[2] = IOwnership.renounceOwnership.selector;
        functionSelectors[3] = IOwnership.transferOwnership.selector;
        functionSelectors[4] = IOwnership.acceptOwnership.selector;

        return IDiamond.FacetCut({
            facetAddress: ownershipFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }

    function deployUtilsFacet(Deployer deployer) internal returns (IDiamond.FacetCut memory) {
        address utilsFacet = create2(deployer, type(UtilsFacet).creationCode);

        bytes4[] memory functionSelectors = new bytes4[](2);
        functionSelectors[0] = IUtils.permit.selector;
        functionSelectors[1] = IUtils.multicall.selector;

        return IDiamond.FacetCut({
            facetAddress: utilsFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }
}
