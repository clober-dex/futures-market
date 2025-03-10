// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IFuturesMarket} from "../src/interfaces/IFuturesMarket.sol";
import {FuturesMarket} from "../src/FuturesMarket.sol";
import {Debt} from "../src/Debt.sol";
import {FacetDeployer} from "../src/helpers/FacetDeployer.sol";

library Deploy {
    function deployFuturesMarket(Vm vm, address oracle, address owner) internal returns (IFuturesMarket) {
        address diamond = address(new FuturesMarket(owner));
        address debtTokenImpl = address(new Debt(diamond));

        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](6);
        cut[0] = FacetDeployer.deployFlashLoanFacet();
        cut[1] = FacetDeployer.deployMarketManagerFacet(oracle, debtTokenImpl);
        cut[2] = FacetDeployer.deployMarketPositionFacet(oracle);
        cut[3] = FacetDeployer.deployMarketViewFacet();
        cut[4] = FacetDeployer.deployOwnershipFacet();
        cut[5] = FacetDeployer.deployUtilsFacet();

        vm.prank(owner);
        IDiamondCut(diamond).diamondCut(cut, address(0), "");

        return IFuturesMarket(diamond);
    }
}
