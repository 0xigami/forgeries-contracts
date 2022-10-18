// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "./Ownable/OwnableUpgradeable.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";

/// @notice VRFNFTRandom Draw with NFT Tickets
/// @author @isiain
/// @dev CODE IS UNAUDITED and UNDER DEVELOPMENT
/// @dev USE AT YOUR OWN RICK
contract VRFNFTRandomDraw is VRFConsumerBaseV2, OwnableUpgradeable {
    /// @notice Reference to chain-specific coordinator contract
    VRFCoordinatorV2Interface immutable coordinator;

    /// @notice Struct to organize user settings
    struct Settings {
        /// @notice Token Contract to put up for raffle
        IERC721EnumerableUpgradeable token;
        /// @notice Token ID to put up for raffle
        uint256 tokenId;
        /// @notice Token that each (sequential) ID has a entry in the raffle.
        IERC721EnumerableUpgradeable drawingToken;
        /// @notice Start token ID for the drawing (if totalSupply = 20 but the first token is 5 (5-25), setting this to 5 would fix the ordering)
        uint256 drawingTokenStartId;
        /// @notice Draw buffer time – time until a re-drawing can occur if the selected user cannot or does not claim the NFT.
        uint256 drawBufferTime;
        /// @notice Number of tokens that can be drawn from, should match totalSupply
        uint256 numberTokens;
        /// @notice block.timestamp that the admin can recover the NFT (as a safety fallback)
        uint256 recoverTimelock;
        /// @notice Chainlink gas keyhash
        bytes32 keyHash;
        /// @notice Chainlink subscription id
        uint64 subscriptionId;
    }

    /// @notice Settings used for the contract.
    Settings public settings;

    /// @notice Struct to organize current request
    struct CurrentRequest {
        /// @notice current chainlink request id
        uint256 currentChainlinkRequestId;
        /// @notice current chosen random number
        uint256 currentChosenTokenId;
        /// @notice has chosen a random number (in case random number = 0(in case random number = 0)(in case random number = 0)(in case random number = 0)(in case random number = 0)(in case random number = 0)(in case random number = 0)(in case random number = 0)(in case random number = 0))
        bool hasChosenRandomNumber;
        /// @notice time lock (block.timestamp) that a re-draw can be issued
        uint256 drawTimelock;
    }

    /// @notice Details about the current request to chainlink
    CurrentRequest private request;

    /// @notice Our callback is just setting a few variables, 200k should be more than enough gas.
    uint32 constant callbackGasLimit = 200_000;
    /// @notice Chainlink request confirmations, left at the default @todo figure out what the correct value is here
    uint16 constant minimumRequestConfirmations = 3;
    /// @notice Number of words requested in a drawing
    uint16 constant wordsRequested = 1;

    /// @notice Cannot redraw during waiting period
    error STILL_IN_WAITING_PERIOD_BEFORE_REDRAWING();
    /// @notice Admin emergency withdraw can only happen once unlocked
    error WITHDRAW_TIMELOCK_NEEDS_TO_BE_IN_FUTURE();
    /// @notice Token that is offered does not exist with ownerOf
    error TOKEN_BEING_OFFERED_NEEDS_TO_EXIST();
    /// @notice Token cannot be at zero address
    error TOKEN_CANNOT_BE_ZERO_ADDRESS();
    /// @notice Token needs to be approved to raffle contract
    error TOKEN_NEEDS_TO_BE_APPROVED_TO_CONTRACT();
    /// @notice Waiting on a response from chainlink
    error REQUEST_IN_FLIGHT();
    /// @notice Chainlink VRF response doesn't match current ID
    error REQUEST_DOES_NOT_MATCH_CURRENT_ID();
    /// @notice The tokens' totalSupply doesn't match one claimed on contract
    error SUPPLY_TOKENS_COUNT_WRONG();
    /// @notice Cannot attempt to claim winnings if request is not started or in flight
    error NEEDS_TO_HAVE_CHOSEN_A_NUMBER();

    /// @notice Withdraw timelock min is 1 hour
    error WITHDRAW_TIMELOCK_NEEDS_TO_BE_AT_LEAST_AN_HOUR();
    /// @notice Admin NFT recovery timelock min is 1 week
    error RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK();
    /// @notice The given user has not won
    error USER_HAS_NOT_WON();
    /// @notice Cannot re-draw yet
    error TOO_SOON_TO_REDRAW();
    /// @notice NFT for raffle is not owned by the admin
    error DOES_NOT_OWN_NFT();
    /// @notice Recovery is too early
    error RECOVERY_IS_NOT_YET_POSSIBLE();
    /// @notice Too many / few random words are sent back from chainlink
    error WRONG_LENGTH_FOR_RANDOM_WORDS();

    /// @notice When the draw is initialized
    event InitializedDraw(address indexed sender, Settings settings);
    /// @notice When the draw is setup
    event SetupDraw(address indexed sender, Settings settings);
    /// @notice When the owner reclaims nft aftr recovery time delay
    event OwnerReclaimedNFT(address indexed owner);
    /// @notice Dice roll is complete from callback
    event DiceRollComplete(address indexed sender, CurrentRequest request);
    /// @notice Sent when the winner sends/claims an NFT
    event WinnerSentNFT(
        address indexed winner,
        address indexed nft,
        uint256 indexed tokenId,
        Settings settings
    );

    /// @dev Save the coordiantor to the contract
    constructor(VRFCoordinatorV2Interface _coordinator)
        VRFConsumerBaseV2(address(_coordinator))
    {
        coordinator = _coordinator;
    }

    /// @notice Getter for request details, does not include picked tokenID
    function getRequestDetails()
        external
        returns (
            uint256 currentChainlinkRequestId,
            bool hasChosenRandomNumber,
            uint256 drawTimelock
        )
    {
        currentChainlinkRequestId = request.currentChainlinkRequestId;
        hasChosenRandomNumber = request.hasChosenRandomNumber;
        drawTimelock = request.drawTimelock;
    }

    /// @notice Initialize the contract with settings and an amind
    /// @param admin initial admin
    /// @param _settings initial settings
    function initialize(address admin, Settings memory _settings)
        public
        initializer
    {
        // Set new settings
        settings = _settings;

        // Check values in memory:
        if (_settings.drawBufferTime < 60 * 60) {
            revert WITHDRAW_TIMELOCK_NEEDS_TO_BE_AT_LEAST_AN_HOUR();
        }

        // If admin recovery is okay
        if (_settings.recoverTimelock != 0) {
            if (_settings.recoverTimelock < block.timestamp + (3600 * 24 * 7)) {
                revert RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK();
            }
        }

        // If NFT contract address is 0x0 throw error
        if (address(_settings.token) == address(0x0)) {
            revert TOKEN_CANNOT_BE_ZERO_ADDRESS();
        }

        // Get owner of raffled tokenId and ensure the current owner is the admin
        try _settings.token.ownerOf(_settings.tokenId) returns (
            address nftOwner
        ) {
            // Check if address is the admin address
            if (nftOwner != admin) {
                revert DOES_NOT_OWN_NFT();
            }
        } catch {
            revert TOKEN_BEING_OFFERED_NEEDS_TO_EXIST();
        }

        // Ensure the total supply is as expected
        try _settings.drawingToken.totalSupply() returns (uint256 supply) {
            // If unset, set to totalSupply
            if (_settings.numberTokens == 0) {
                settings.numberTokens = supply;
            } else if (supply != _settings.numberTokens) {
                revert SUPPLY_TOKENS_COUNT_WRONG();
            }
        } catch {
            // If not supported, user will verify count.
        }

        // Setup owner as admin
        __Ownable_init(admin);

        // Emit initialized event for indexing
        emit InitializedDraw(msg.sender, settings);
    }

    /// @notice Internal function to request entropy
    function _requestRoll() internal {
        // Owner of token to raffle needs to be this contract
        if (settings.token.ownerOf(settings.tokenId) != address(this)) {
            revert DOES_NOT_OWN_NFT();
        }

        // Chainlink request cannot be currently in flight.
        // Request is cleared in re-roll if conditions are correct.
        if (request.currentChainlinkRequestId != 0) {
            revert REQUEST_IN_FLIGHT();
        }

        // If the number has been drawn and
        if (
            request.hasChosenRandomNumber &&
            // Draw timelock not yet used
            request.drawTimelock != 0 &&
            request.drawTimelock > block.timestamp
        ) {
            revert STILL_IN_WAITING_PERIOD_BEFORE_REDRAWING();
        }

        // Setup re-draw timelock
        request.drawTimelock = block.timestamp + settings.drawBufferTime;

        // Request first random round
        request.currentChainlinkRequestId = coordinator.requestRandomWords({
            keyHash: settings.keyHash,
            subId: settings.subscriptionId,
            minimumRequestConfirmations: minimumRequestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: wordsRequested
        });
    }

    /// @notice Call this to start the raffle drawing
    /// @return chainlink request id
    function startDraw() external onlyOwner returns (uint256) {
        // Only can be called on first drawing
        if (request.currentChainlinkRequestId != 0) {
            revert REQUEST_IN_FLIGHT();
        }

        // Attempt to transfer toke into this address
        try
            settings.token.transferFrom(
                msg.sender,
                address(this),
                settings.tokenId
            )
        {} catch {
            revert TOKEN_NEEDS_TO_BE_APPROVED_TO_CONTRACT();
        }

        // Emit setup draw user event
        emit SetupDraw(msg.sender, settings);

        // Request initial roll
        _requestRoll();

        // Return the current chainlink request id
        return request.currentChainlinkRequestId;
    }

    /// @notice Call this to re-draw the raffle
    /// @return chainlink request ID
    function redraw() external onlyOwner returns (uint256) {
        if (request.drawTimelock >= block.timestamp) {
            revert TOO_SOON_TO_REDRAW();
        }

        // Reset request
        delete request;

        // Re-roll
        _requestRoll();

        // Return current chainlink request ID
        return request.currentChainlinkRequestId;
    }

    /// @notice Function called by chainlink to resolve random words
    /// @param _requestId ID of request sent to chainlink VRF
    /// @param _randomWords List of uint256 words of random entropy
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        // Validate request ID
        if (_requestId != request.currentChainlinkRequestId) {
            revert REQUEST_DOES_NOT_MATCH_CURRENT_ID();
        }

        // Validate number of words returned
        if (_randomWords.length != wordsRequested) {
            revert WRONG_LENGTH_FOR_RANDOM_WORDS();
        }

        // Set request details
        request.hasChosenRandomNumber = true;
        request.currentChosenTokenId =
            (_randomWords[0] % settings.numberTokens) +
            settings.drawingTokenStartId;

        // Emit indexer event
        emit DiceRollComplete(msg.sender, request);
    }

    function hasUserWon(address user) public view returns (bool) {
        if (!request.hasChosenRandomNumber) {
            revert NEEDS_TO_HAVE_CHOSEN_A_NUMBER();
        }

        return
            user == settings.drawingToken.ownerOf(request.currentChosenTokenId);
    }

    /// @notice Function for the winner to call to retrieve their NFT
    function winnerClaimNFT() external {
        // Assume (potential) winner calls this fn, cache.
        address user = msg.sender;

        // Check if this user has indeed won.
        if (!hasUserWon(user)) {
            revert USER_HAS_NOT_WON();
        }

        // Transfer token to the winter.
        settings.token.transferFrom(
            address(this),
            msg.sender,
            settings.tokenId
        );

        // Emit a celebratory event
        emit WinnerSentNFT(
            user,
            address(settings.token),
            settings.tokenId,
            settings
        );
    }

    /// @notice Optional last resort admin reclaim nft function
    function lastResortTimelockOwnerClaimNFT() external onlyOwner {
        // If recoverTimelock is not setup, or if not yet occurred
        if (
            settings.recoverTimelock == 0 ||
            settings.recoverTimelock > block.timestamp
        ) {
            // Stop the withdraw
            revert RECOVERY_IS_NOT_YET_POSSIBLE();
        }

        // Otherwise, process the withdraw
        settings.token.transferFrom(address(this), owner(), settings.tokenId);

        // Send event for indexing that the owner reclaimed the NFT
        emit OwnerReclaimedNFT(owner());
    }
}
