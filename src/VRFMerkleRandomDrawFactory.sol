// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";
import {ClonesUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

import {VRFMerkleRandomDraw} from "./VRFMerkleRandomDraw.sol";


/// @notice VRFNFTRandom Draw with NFT Tickets Factory
/// @author @isiain
/// @dev CODE IS UNAUDITED and UNDER DEVELOPMENT
/// @dev USE AT YOUR OWN RICK
contract VRFMerkleRandomDrawFactory {
    /// @notice Implementation to clone of the raffle code
    address public immutable implementation;

    /// @notice Event emitted when a new drawing contract is created
    event SetupNewDrawing(address user, address drawing);

    /// @notice Constructor to set the implementation
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /// @notice Function to make a new drawing
    /// @param settings settings for the new drawing
    function makeNewDraw(VRFMerkleRandomDraw.Settings memory settings)
        external
        returns (address)
    {
        address admin = msg.sender;
        // Clone the contract
        address newDrawing = ClonesUpgradeable.clone(implementation);
        // Setup the new drawing
        VRFMerkleRandomDraw(newDrawing).initialize(admin, settings);
        // Emit event for indexing
        emit SetupNewDrawing(admin, newDrawing);
        // Return address for integration or testing
        return newDrawing;
    }
}
