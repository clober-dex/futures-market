// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

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

library FacetDeployer {
    function deployFlashLoanFacet() internal returns (IDiamond.FacetCut memory) {
        address flashLoanFacet = address(new FlashLoanFacet());
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

    function deployMarketManagerFacet(address oracle, address debtTokenImpl)
        internal
        returns (IDiamond.FacetCut memory)
    {
        address marketManagerFacet = address(new MarketManagerFacet(oracle, debtTokenImpl));
        bytes4[] memory functionSelectors = new bytes4[](3);
        functionSelectors[0] = IMarketManager.open.selector;
        functionSelectors[1] = IMarketManager.settle.selector;
        functionSelectors[2] = IMarketManager.updateOracle.selector;

        return IDiamond.FacetCut({
            facetAddress: marketManagerFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
    }

    function deployMarketPositionFacet(address oracle) internal returns (IDiamond.FacetCut memory) {
        address marketPositionFacet = address(new MarketPositionFacet(oracle));
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

    function deployMarketViewFacet() internal returns (IDiamond.FacetCut memory) {
        address marketViewFacet = address(new MarketViewFacet());
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

    function deployOwnershipFacet() internal returns (IDiamond.FacetCut memory) {
        address ownershipFacet = address(new OwnershipFacet());
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

    function deployUtilsFacet() internal returns (IDiamond.FacetCut memory) {
        address utilsFacet = address(new UtilsFacet());
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
