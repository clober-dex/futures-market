// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CreateX} from "diamond/helpers/CreateX.sol";
import {DiamondScript} from "diamond/helpers/DiamondScript.sol";
import {IDiamond} from "diamond/helpers/DiamondScript.sol";

import {PythOracle} from "../src/PythOracle.sol";
import {Debt} from "../src/Debt.sol";
import {Init} from "../src/helpers/Init.sol";

contract DeployScript is DiamondScript("FuturesMarket") {
    function setUp() public {}

    function deployOracle() public broadcast {
        address deployer = msg.sender;
        address owner = deployer;
        address pyth = 0x2880aB155794e7179c9eE2e38200202908C17B43;
        uint256 interval = 60;
        address implementation =
            CreateX.create2(deployer, abi.encodePacked(type(PythOracle).creationCode, abi.encode(pyth, interval)));
        console.log("Oracle implementation deployed at", address(implementation));

        bytes11 salt = bytes11(keccak256(abi.encode("PythOracle", 0)));
        address oracle = CreateX.create3(
            deployer,
            salt,
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementation, abi.encodeWithSelector(PythOracle.initialize.selector, owner))
            )
        );
        console.log("Oracle deployed at", oracle);
    }

    function deployMarket(address oracle) public broadcast {
        address deployer = msg.sender;
        address owner = deployer;

        bytes32 salt = bytes32(0);
        address expectedMarketAddress = computeDiamondAddress(deployer, salt);
        address debtTokenImpl =
            CreateX.create2(deployer, abi.encodePacked(type(Debt).creationCode, abi.encode(expectedMarketAddress)));

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

        address init = address(new Init());

        address market = deploy(
            abi.encode(owner), salt, facetNames, facetArgs, init, abi.encodeWithSelector(Init.init.selector)
        ).diamond;
        require(address(market) == expectedMarketAddress, "Market address does not match");

        console.log("FuturesMarket deployed at", address(market));
    }
}
