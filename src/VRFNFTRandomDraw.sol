// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721.sol';


contract VRFNFTRandomDraw is OwnableUpgradeable {
    address token;
    uint256 tokenId;
    uint256 numberApplicants;
    uint256 withdrawTimelock;

    error WITHDRAW_TIMELOCK_NEEDS_TO_BE_IN_FUTURE();
    
    function initialize(IERC721Upgrdeable _token, uint256 tokenId, uint256 _withdrawTimelock) initializer {
        if (_withdrawTimelock < 3600*7) {
            revert WITHDRAW_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK();
        }
        withdrawTimelock = _withdrawTimelock;
        token = _token;
        IERC721Upgradeable(token).transferFrom(msg.sender, address(this));
    }

    function startDraw() {

    }

    function finalizeWinner() {

    }
}
