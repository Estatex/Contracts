// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

import "../@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BUSDToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("BUSD", "BUSD") {
        _mint(msg.sender, initialSupply);
    }
}