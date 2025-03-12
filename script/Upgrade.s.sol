// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FacetDeployer, Deployer} from "../src/helpers/FacetDeployer.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {FlashLoanFacet} from "../src/facets/FlashLoanFacet.sol";
import {MarketManagerFacet} from "../src/facets/MarketManagerFacet.sol";
import {MarketPositionFacet} from "../src/facets/MarketPositionFacet.sol";
import {MarketViewFacet} from "../src/facets/MarketViewFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {UtilsFacet} from "../src/facets/UtilsFacet.sol";

contract UpgradeScript is Script {
    using stdJson for string;
    using FacetDeployer for Deployer;

    Deployer internal deployer;
    string internal json;
    address internal futuresMarket;

    // tmp vars
    bytes4[] internal addSelectors;
    bytes4[] internal replaceSelectors;

    IDiamond.FacetCut[] internal cuts;
    bytes4[] internal removeSelectors;

    constructor() {
        json =
            vm.readFile(string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), "/addresses.json"));

        futuresMarket = json.readAddress(".FuturesMarket");
    }

    function upgradeAll() public {
        deployer = Deployer.wrap(msg.sender);

        vm.startBroadcast();

        _buildCut(
            "FlashLoanFacet", FacetDeployer.getFlashLoanFacetInitCode(), FacetDeployer.getFlashLoanFacetSelectors()
        );
        _buildCut(
            "MarketManagerFacet",
            FacetDeployer.getMarketManagerFacetInitCode(
                json.readAddress(".PythOracle"), json.readAddress(".DebtTokenImpl")
            ),
            FacetDeployer.getMarketManagerFacetSelectors()
        );
        _buildCut(
            "MarketPositionFacet",
            FacetDeployer.getMarketPositionFacetInitCode(json.readAddress(".PythOracle")),
            FacetDeployer.getMarketPositionFacetSelectors()
        );
        _buildCut(
            "MarketViewFacet", FacetDeployer.getMarketViewFacetInitCode(), FacetDeployer.getMarketViewFacetSelectors()
        );
        _buildCut(
            "OwnershipFacet", FacetDeployer.getOwnershipFacetInitCode(), FacetDeployer.getOwnershipFacetSelectors()
        );
        _buildCut("UtilsFacet", FacetDeployer.getUtilsFacetInitCode(), FacetDeployer.getUtilsFacetSelectors());
        _applyCuts();

        vm.stopBroadcast();
    }

    function upgradeFlashLoanFacet() public {
        deployer = Deployer.wrap(msg.sender);
        vm.startBroadcast();
        _buildCut(
            "FlashLoanFacet", FacetDeployer.getFlashLoanFacetInitCode(), FacetDeployer.getFlashLoanFacetSelectors()
        );
        _applyCuts();
        vm.stopBroadcast();
    }

    function upgradeMarketManagerFacet() public {
        deployer = Deployer.wrap(msg.sender);
        vm.startBroadcast();
        _buildCut(
            "MarketManagerFacet",
            FacetDeployer.getMarketManagerFacetInitCode(
                json.readAddress(".PythOracle"), json.readAddress(".DebtTokenImpl")
            ),
            FacetDeployer.getMarketManagerFacetSelectors()
        );
        _applyCuts();
        vm.stopBroadcast();
    }

    function upgradeMarketPositionFacet() public {
        deployer = Deployer.wrap(msg.sender);
        vm.startBroadcast();
        _buildCut(
            "MarketPositionFacet",
            FacetDeployer.getMarketPositionFacetInitCode(json.readAddress(".PythOracle")),
            FacetDeployer.getMarketPositionFacetSelectors()
        );
        _applyCuts();
        vm.stopBroadcast();
    }

    function upgradeMarketViewFacet() public {
        deployer = Deployer.wrap(msg.sender);
        vm.startBroadcast();
        _buildCut(
            "MarketViewFacet", FacetDeployer.getMarketViewFacetInitCode(), FacetDeployer.getMarketViewFacetSelectors()
        );
        _applyCuts();
        vm.stopBroadcast();
    }

    function upgradeOwnershipFacet() public {
        deployer = Deployer.wrap(msg.sender);
        vm.startBroadcast();
        _buildCut(
            "OwnershipFacet", FacetDeployer.getOwnershipFacetInitCode(), FacetDeployer.getOwnershipFacetSelectors()
        );
        _applyCuts();
        vm.stopBroadcast();
    }

    function upgradeUtilsFacet() public {
        deployer = Deployer.wrap(msg.sender);
        vm.startBroadcast();
        _buildCut("UtilsFacet", FacetDeployer.getUtilsFacetInitCode(), FacetDeployer.getUtilsFacetSelectors());
        _applyCuts();
        vm.stopBroadcast();
    }

    function _buildCut(string memory facetName, bytes memory initCode, bytes4[] memory newSelectors) internal {
        address newFacet = deployer.create2(initCode);
        address oldFacet = json.readAddress(string.concat(".", facetName));

        if (oldFacet == newFacet) {
            console.log(string.concat(facetName, " is up to date"));
            return;
        }

        console.log(string.concat("Upgrading ", facetName));
        console.log(string.concat("Old facet: ", vm.toString(oldFacet)));
        console.log(string.concat("New facet: ", vm.toString(newFacet)));

        addSelectors = new bytes4[](0);
        replaceSelectors = new bytes4[](0);
        removeSelectors = new bytes4[](0);

        for (uint256 i; i < newSelectors.length; ++i) {
            address remoteFacet = IDiamondLoupe(futuresMarket).facetAddress(newSelectors[i]);
            if (remoteFacet == address(0)) {
                console.log(string.concat("Adding selector ", vm.toString(newSelectors[i])));
                addSelectors.push(newSelectors[i]);
            } else if (remoteFacet == oldFacet) {
                console.log(string.concat("Replacing selector ", vm.toString(newSelectors[i])));
                replaceSelectors.push(newSelectors[i]);
            } else {
                revert("Invalid selector");
            }
        }

        bytes4[] memory oldSelectors = IDiamondLoupe(futuresMarket).facetFunctionSelectors(oldFacet);
        for (uint256 i = 0; i < oldSelectors.length; ++i) {
            bool found = false;
            for (uint256 j = 0; j < newSelectors.length; ++j) {
                if (oldSelectors[i] == newSelectors[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                console.log(string.concat("Removing selector ", vm.toString(oldSelectors[i])));
                removeSelectors.push(oldSelectors[i]);
            }
        }
        if (addSelectors.length > 0) {
            cuts.push(
                IDiamond.FacetCut({
                    facetAddress: newFacet,
                    action: IDiamond.FacetCutAction.Add,
                    functionSelectors: addSelectors
                })
            );
        }
        if (replaceSelectors.length > 0) {
            cuts.push(
                IDiamond.FacetCut({
                    facetAddress: newFacet,
                    action: IDiamond.FacetCutAction.Replace,
                    functionSelectors: replaceSelectors
                })
            );
        }
    }

    function _applyCuts() internal {
        if (removeSelectors.length > 0) {
            cuts.push(
                IDiamond.FacetCut({
                    facetAddress: address(0),
                    action: IDiamond.FacetCutAction.Remove,
                    functionSelectors: removeSelectors
                })
            );
        }

        if (cuts.length > 0) {
            IDiamondCut(futuresMarket).diamondCut(cuts, address(0), "");
        } else {
            console.log("No changes to apply");
        }
    }
}
