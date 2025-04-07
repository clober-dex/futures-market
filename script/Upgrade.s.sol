// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {CreateX} from "diamond/helpers/CreateX.sol";
import {DiamondScript} from "diamond/helpers/DiamondScript.sol";
import {Debt} from "../src/Debt.sol";

contract UpgradeScript is DiamondScript("FuturesMarket") {
    using stdJson for string;

    function upgradeAll() public broadcast {
        string memory json = loadDeployment();

        address deployer = msg.sender;
        address oracle = json.readAddress(".PythOracle");
        address marketAddress = computeDiamondAddress(deployer, bytes32(0));
        address debtTokenImpl =
            CreateX.create2(deployer, abi.encodePacked(type(Debt).creationCode, abi.encode(marketAddress)));

        string[] memory facetNames = new string[](5);
        bytes[] memory facetArgs = new bytes[](5);

        facetNames[0] = "FlashLoanFacet";
        facetArgs[0] = abi.encode("");
        facetNames[1] = "MarketManagerFacet";
        facetArgs[1] = abi.encode(oracle, debtTokenImpl);
        facetNames[2] = "MarketPositionFacet";
        facetArgs[2] = abi.encode(oracle);
        facetNames[3] = "MarketViewFacet";
        facetArgs[3] = abi.encode("");
        facetNames[4] = "UtilsFacet";
        facetArgs[4] = abi.encode("");

        upgrade(facetNames, facetArgs, address(0), "");
    }
}
