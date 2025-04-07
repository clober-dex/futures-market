// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console, stdJson} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CreateX} from "diamond/helpers/CreateX.sol";
import {DiamondScript} from "diamond/helpers/DiamondScript.sol";
import {IDiamond} from "diamond/helpers/DiamondScript.sol";

import {PythOracle} from "../src/PythOracle.sol";
import {Debt} from "../src/Debt.sol";
import {Init} from "../src/helpers/Init.sol";
import {Constant} from "../src/helpers/Constant.sol";

contract DeployScript is DiamondScript("FuturesMarket") {
    using stdJson for string;

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

    function deployMarket() public broadcast {
        string memory json = loadDeployment();

        address deployer = msg.sender;
        address owner = deployer;
        address oracle = json.readAddress(".PythOracle");

        bytes32 salt = Constant.SALT;
        address expectedMarketAddress = computeDiamondAddress(deployer, salt);
        address debtTokenImpl =
            CreateX.create2(deployer, abi.encodePacked(type(Debt).creationCode, abi.encode(expectedMarketAddress)));

        (string[] memory facetNames, bytes[] memory facetArgs) = Constant.getFacetData(oracle, debtTokenImpl);

        address init = address(new Init());

        address market = deploy(
            abi.encode(owner), salt, facetNames, facetArgs, init, abi.encodeWithSelector(Init.init.selector)
        ).diamond;
        require(address(market) == expectedMarketAddress, "Market address does not match");

        console.log("FuturesMarket deployed at", address(market));
    }
}
