// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IFuturesMarket} from "../src/interfaces/IFuturesMarket.sol";
import {FuturesMarket} from "../src/FuturesMarket.sol";
import {Debt} from "../src/Debt.sol";
import {FacetDeployer, Deployer} from "../src/helpers/FacetDeployer.sol";
import {Init} from "../src/helpers/Init.sol";
import {CREATEX_ADDRESS, CREATEX_BYTECODE} from "../src/helpers/CreateX.sol";

library Deploy {
    using FacetDeployer for Deployer;

    function deployFuturesMarket(Vm vm, Deployer deployer, address oracle, address owner)
        internal
        returns (IFuturesMarket)
    {
        vm.label(CREATEX_ADDRESS, "CreateX");
        vm.etch(CREATEX_ADDRESS, CREATEX_BYTECODE);

        bytes32 salt = bytes32(
            abi.encodePacked(Deployer.unwrap(deployer), hex"00", bytes11(keccak256(abi.encode("FuturesMarket", 0))))
        );
        address diamond = deployer.create3(salt, abi.encodePacked(type(FuturesMarket).creationCode, abi.encode(owner)));
        salt = bytes32(abi.encodePacked(Deployer.unwrap(deployer), hex"00", bytes11(keccak256(abi.encode("Debt", 0)))));
        address debtTokenImpl = deployer.create2(salt, abi.encodePacked(type(Debt).creationCode, abi.encode(diamond)));

        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](6);
        cut[0] = deployer.deployFlashLoanFacet();
        cut[1] = deployer.deployMarketManagerFacet(oracle, debtTokenImpl);
        cut[2] = deployer.deployMarketPositionFacet(oracle);
        cut[3] = deployer.deployMarketViewFacet();
        cut[4] = deployer.deployOwnershipFacet();
        cut[5] = deployer.deployUtilsFacet();

        address init = address(new Init());

        vm.prank(owner);
        IDiamondCut(diamond).diamondCut(cut, init, abi.encodeWithSelector(Init.init.selector));

        return IFuturesMarket(diamond);
    }
}
