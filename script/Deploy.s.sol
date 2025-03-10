// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PythOracle} from "../src/PythOracle.sol";
import {Debt} from "../src/Debt.sol";
import {FuturesMarket} from "../src/FuturesMarket.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {FacetDeployer} from "../src/helpers/FacetDeployer.sol";
import {Init} from "../src/helpers/Init.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address owner = 0x5F79EE8f8fA862E98201120d83c4eC39D9468D49;
        address pyth = 0x2880aB155794e7179c9eE2e38200202908C17B43;
        uint256 interval = 60;
        PythOracle oracle = PythOracle(
            address(
                new ERC1967Proxy(
                    address(new PythOracle(pyth, interval)),
                    abi.encodeWithSelector(PythOracle.initialize.selector, owner)
                )
            )
        );
        console.log("Oracle deployed at", address(oracle));

        address diamond = address(new FuturesMarket(owner));
        address debtTokenImpl = address(new Debt(diamond));
        console.log("Diamond deployed at", address(diamond));
        console.log("DebtTokenImpl deployed at", address(debtTokenImpl));

        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](6);
        cut[0] = FacetDeployer.deployFlashLoanFacet();
        cut[1] = FacetDeployer.deployMarketManagerFacet(address(oracle), debtTokenImpl);
        cut[2] = FacetDeployer.deployMarketPositionFacet(address(oracle));
        cut[3] = FacetDeployer.deployMarketViewFacet();
        cut[4] = FacetDeployer.deployOwnershipFacet();
        cut[5] = FacetDeployer.deployUtilsFacet();

        address init = address(new Init());

        IDiamondCut(diamond).diamondCut(cut, init, abi.encodeWithSelector(Init.init.selector));

        vm.stopBroadcast();
    }
}
