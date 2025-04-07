// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {CreateX} from "diamond/helpers/CreateX.sol";
import {DiamondScript} from "diamond/helpers/DiamondScript.sol";
import {Debt} from "../src/Debt.sol";
import {Constant} from "../src/helpers/Constant.sol";

contract UpgradeScript is DiamondScript("FuturesMarket") {
    using stdJson for string;

    function upgradeAll() public broadcast {
        string memory json = loadDeployment();

        address deployer = msg.sender;
        address oracle = json.readAddress(".PythOracle");
        address marketAddress = computeDiamondAddress(deployer, Constant.SALT);
        address debtTokenImpl =
            CreateX.create2(deployer, abi.encodePacked(type(Debt).creationCode, abi.encode(marketAddress)));

        (string[] memory facetNames, bytes[] memory facetArgs) = Constant.getFacetData(oracle, debtTokenImpl);

        upgrade(facetNames, facetArgs, address(0), "");
    }
}
