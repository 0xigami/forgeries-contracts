// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";
import {ClonesUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

import {VRFNFTRandomDraw} from "./VRFNFTRandomDraw.sol";

contract VRFNFTRandomDrawFactory {
    address immutable implementation;

    event SetupNewDrawing(address user, address drawing);

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function makeNewDraw(VRFNFTRandomDraw.Settings memory settings)
        external
        returns (address)
    {
        address admin = msg.sender;
        address newDrawing = ClonesUpgradeable.clone(implementation);
        VRFNFTRandomDraw(newDrawing).initialize(admin, settings);
        emit SetupNewDrawing(admin, newDrawing);
        return newDrawing;
    }
}
