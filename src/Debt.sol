// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract Debt is ERC20PermitUpgradeable {
    address internal immutable _manager;

    constructor(address manager_) {
        _manager = manager_;
    }

    function initialize(string memory name, string memory symbol) external initializer {
        __ERC20Permit_init(name);
        __ERC20_init(name, symbol);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == _manager, "Not manager");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == _manager, "Not manager");
        _burn(from, amount);
    }
}
