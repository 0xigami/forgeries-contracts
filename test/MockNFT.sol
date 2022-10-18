// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721} from "solmate/tokens/ERC721.sol";

contract MockNFT is ERC721 {
    uint256 at;
    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}
    function tokenURI(uint256) public pure override returns (string memory) {
      return '';
    }
    function mint() external {
        _mint(msg.sender, at++);
    }

    function totalSupply() external view returns (uint256) {
        return at;
    }
}
