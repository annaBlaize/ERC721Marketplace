// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract ERC20Mock is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { 
        _mint(msg.sender, 10**22);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
