// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PythOracle} from "../src/PythOracle.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {Debt} from "../src/Debt.sol";

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

        address vaultManagerImpl = address(new VaultManager(address(oracle)));
        address vaultManagerProxy = address(new ERC1967Proxy(vaultManagerImpl, ""));
        address debtTokenImpl = address(new Debt(vaultManagerProxy));
        VaultManager vaultManager = VaultManager(vaultManagerProxy);
        vaultManager.initialize(owner, debtTokenImpl);
        console.log("VaultManager deployed at", address(vaultManager));

        vm.stopBroadcast();
    }

    function upgradeVaultManager() public {
        address oracle = 0x0Ac256AE2a360CB85e57ac1860608ae3372aA0BF;
        vm.startBroadcast();
        address newTemplate = address(new VaultManager(address(oracle)));
        VaultManager(0xAa7a07414d23F1153ED13C702CB84c5DD1319a62).upgradeToAndCall(newTemplate, "");
        vm.stopBroadcast();
    }
}
