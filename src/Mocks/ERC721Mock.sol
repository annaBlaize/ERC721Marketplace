// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";

contract ERC721Mock is ERC721, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) { }

    function mint(address to) external onlyOwner {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(to, newItemId);
    }

    
}
