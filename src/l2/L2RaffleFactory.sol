// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Clones} from "@openzeppelin/contracts/utils/Clones.sol";

contract L2RaffleFactory is OwnableUpgradeable, IERC721Receiever, IERC1155Receiver {
    address immutable l2RaffleImpl;
    event SetupFactory(address impl);

    mapping(address => mapping(uint256 => uint256)) public contractTokenInstances;

    constructor(address l2RaffleImpl_) {
        l2RaffleImpl = l2RaffleImpl_; 
        emit SetupFactory(l2RaffleImpl);
    }

    function predictAddress(address target, uint256 tokenId) public view returns (address) {
        uint256 instance = contractTokenInstances[target][tokenId];
        return Clones.predictDeterministicAddress(l2RaffleImpl_, abi.encode(target, tokenId, instance), address(this));
    }

    function _cloneAndSetupContract(address target, uint256 tokenId) {
        uint256 instance = contractTokenInstances[target][tokenId]++;
        Clones.cloneDeterministic(l2RaffleImpl_, abi.encode(target, tokenId, instance));
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {

        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(operator, from, id, value, data) external returns (bytes4) {
        _cloneAndSetupContract({
                
        });
        IERC1155(msg.sender).

        return IERC1155Receiver.onERC1155Received.selector;
    }



}