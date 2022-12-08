// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";
import {ClonesUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {VRFNFTRandomDraw} from "./VRFNFTRandomDraw.sol";

/// @notice VRFNFTRandom Draw with NFT Tickets Factory
/// @author @isiain
contract VRFNFTRandomDrawFactory {
    /// @notice Implementation to clone of the raffle code
    address public immutable implementation;

    /// @notice Cannot be initialized with a zero address impl.
    error IMPL_ZERO_ADDRESS_NOT_ALLOWED();

    /// @notice Event emitted when a new drawing contract is created
    event SetupNewDrawing(address user, address drawing);

    /// @notice Emitted when the factory is setup
    event SetupFactory();

    /// @notice Constructor to set the implementation
    constructor(address _implementation) {
        if (_implementation == address(0)) {
            revert IMPL_ZERO_ADDRESS_NOT_ALLOWED();
        }
        implementation = _implementation;
        emit SetupFactory();
    }

    /// @notice Function to make a new drawing
    /// @param settings settings for the new drawing
    function makeNewDraw(VRFNFTRandomDraw.Settings memory settings)
        external
        returns (address)
    {
        address admin = msg.sender;
        // Clone the contract
        address newDrawing = ClonesUpgradeable.clone(implementation);
        // Setup the new drawing
        VRFNFTRandomDraw(newDrawing).initialize(admin, settings);
        // Emit event for indexing
        emit SetupNewDrawing(admin, newDrawing);
        // Return address for integration or testing
        return newDrawing;
    }
}
