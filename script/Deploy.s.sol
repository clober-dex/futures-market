// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PythOracle} from "../src/PythOracle.sol";
import {Debt} from "../src/Debt.sol";
import {FuturesMarket} from "../src/FuturesMarket.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {FacetDeployer, Deployer} from "../src/helpers/FacetDeployer.sol";
import {Init} from "../src/helpers/Init.sol";

contract DeployScript is Script {
    using FacetDeployer for Deployer;

    function setUp() public {}

    function deployOracle() public returns (address oracle) {
        vm.startBroadcast();

        Deployer deployer = Deployer.wrap(msg.sender);
        address owner = msg.sender;
        address pyth = 0x2880aB155794e7179c9eE2e38200202908C17B43;
        uint256 interval = 60;
        address implementation =
            deployer.create2(abi.encodePacked(type(PythOracle).creationCode, abi.encode(pyth, interval)));
        console.log("Oracle implementation deployed at", address(implementation));

        bytes32 salt = bytes32(
            abi.encodePacked(Deployer.unwrap(deployer), hex"00", bytes11(keccak256(abi.encode("PythOracle", 0))))
        );
        oracle = deployer.create3(
            salt,
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementation, abi.encodeWithSelector(PythOracle.initialize.selector, owner))
            )
        );
        console.log("Oracle deployed at", oracle);
        vm.stopBroadcast();
    }

    function deployMarket(address oracle) public {
        vm.startBroadcast();

        Deployer deployer = Deployer.wrap(msg.sender);
        address owner = msg.sender;

        bytes32 salt = bytes32(
            abi.encodePacked(Deployer.unwrap(deployer), hex"00", bytes11(keccak256(abi.encode("FuturesMarket", 0))))
        );
        address diamond = deployer.create3(salt, abi.encodePacked(type(FuturesMarket).creationCode, abi.encode(owner)));
        address debtTokenImpl = deployer.create2(abi.encodePacked(type(Debt).creationCode, abi.encode(diamond)));
        console.log("Diamond deployed at", address(diamond));
        console.log("DebtTokenImpl deployed at", address(debtTokenImpl));

        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](6);
        cut[0] = deployer.deployFlashLoanFacet();
        console.log("FlashLoanFacet deployed at", address(cut[0].facetAddress));
        cut[1] = deployer.deployMarketManagerFacet(address(oracle), debtTokenImpl);
        console.log("MarketManagerFacet deployed at", address(cut[1].facetAddress));
        cut[2] = deployer.deployMarketPositionFacet(address(oracle));
        console.log("MarketPositionFacet deployed at", address(cut[2].facetAddress));
        cut[3] = deployer.deployMarketViewFacet();
        console.log("MarketViewFacet deployed at", address(cut[3].facetAddress));
        cut[4] = deployer.deployOwnershipFacet();
        console.log("OwnershipFacet deployed at", address(cut[4].facetAddress));
        cut[5] = deployer.deployUtilsFacet();
        console.log("UtilsFacet deployed at", address(cut[5].facetAddress));

        address init = address(new Init());

        IDiamondCut(diamond).diamondCut(cut, init, abi.encodeWithSelector(Init.init.selector));

        vm.stopBroadcast();
    }
}
