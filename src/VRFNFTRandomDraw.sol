// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {OwnableUpgradeable} from "./Ownable/OwnableUpgradeable.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2, VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";

/// @notice VRFNFTRandom Draw with NFT Tickets
/// @author @isiain
contract VRFNFTRandomDraw is VRFConsumerBaseV2, OwnableUpgradeable {
    /// @notice Reference to chain-specific coordinator contract
    VRFCoordinatorV2Interface immutable coordinator;

    /// @notice Struct to organize user settings
    struct Settings {
        /// @notice Token Contract to put up for raffle
        address token;
        /// @notice Token ID to put up for raffle
        uint256 tokenId;
        /// @notice Token that each (sequential) ID has a entry in the raffle.
        address drawingToken;
        /// @notice Start token ID for the drawing (if totalSupply = 20 but the first token is 5 (5-25), setting this to 5 would fix the ordering)
        uint256 drawingTokenStartId;
        /// @notice End token ID for the drawing (exclusive) (token ids 0 - 9 would be 10 in this field)
        uint256 drawingTokenEndId;
        /// @notice Draw buffer time – time until a re-drawing can occur if the selected user cannot or does not claim the NFT.
        uint256 drawBufferTime;
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
    CurrentRequest public request;

    /// @notice Our callback is just setting a few variables, 200k should be more than enough gas.
    uint32 immutable callbackGasLimit = 200_000;
    /// @notice Chainlink request confirmations, left at the default
    uint16 immutable minimumRequestConfirmations = 3;
    /// @notice Number of words requested in a drawing
    uint16 immutable wordsRequested = 1;

    /// @dev 60 seconds in a min, 60 mins in an hour
    uint256 immutable HOUR_IN_SECONDS = 60 * 60;
    /// @dev 24 hours in a day 7 days in a week
    uint256 immutable WEEK_IN_SECONDS = (3600 * 24 * 7);

    /// @notice Cannot redraw during waiting period
    error STILL_IN_WAITING_PERIOD_BEFORE_REDRAWING();
    /// @notice Admin emergency withdraw can only happen once unlocked
    error WITHDRAW_TIMELOCK_NEEDS_TO_BE_IN_FUTURE();
    /// @notice Token that is offered does not exist with ownerOf
    error TOKEN_BEING_OFFERED_NEEDS_TO_EXIST();
    /// @notice Token needs to be a contract when initializing
    error TOKEN_NEEDS_TO_BE_A_CONTRACT(address potentialTokenAddress);
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

    /// @notice When the range is [20,0] (from 20 to 0, that doesn't make sense)
    error DRAWING_TOKEN_RANGE_INVALID();
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

    /// @dev Save the coordinator to the contract
    /// @param _coordinator Address for VRF Coordinator V2 Interface
    constructor(VRFCoordinatorV2Interface _coordinator)
        VRFConsumerBaseV2(address(_coordinator))
        initializer
    {
        coordinator = _coordinator;
    }

    /// @notice Getter for request details, does not include picked tokenID
    /// @return currentChainlinkRequestId Current Chainlink Request ID
    /// @return hasChosenRandomNumber If the random number for the drawing has been chosen
    /// @return drawTimelock block.timestamp when a redraw can be issued
    function getRequestDetails()
        external
        view
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

    /// @notice Initialize the contract with settings and an admin
    /// @param admin initial admin user
    /// @param _settings initial settings for draw
    function initialize(address admin, Settings memory _settings)
        public
        initializer
    {
        // Set new settings
        settings = _settings;

        // Check values in memory:
        if (_settings.drawBufferTime < HOUR_IN_SECONDS) {
            revert WITHDRAW_TIMELOCK_NEEDS_TO_BE_AT_LEAST_AN_HOUR();
        }

        // If admin recovery is okay
        if (_settings.recoverTimelock != 0) {
            if (_settings.recoverTimelock < block.timestamp + WEEK_IN_SECONDS) {
                revert RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK();
            }
        }

        // If NFT contract address is not a contract
        if (_settings.token.code.length == 0) {
            revert TOKEN_NEEDS_TO_BE_A_CONTRACT(_settings.token);
        }

        // If drawing token is not a contract
        if (_settings.drawingToken.code.length == 0) {
            revert TOKEN_NEEDS_TO_BE_A_CONTRACT(_settings.drawingToken);
        }

        // Validate token range: end needs to be greater than start
        // and the size of the range needs to be at least 2 (end is exclusive)
        if (
            _settings.drawingTokenEndId < _settings.drawingTokenStartId ||
            _settings.drawingTokenEndId -
            _settings.drawingTokenStartId < 2
        ) {
            revert DRAWING_TOKEN_RANGE_INVALID();
        }

        // Setup owner as admin
        __Ownable_init(admin);

        // Emit initialized event for indexing
        emit InitializedDraw(msg.sender, settings);

        // Get owner of raffled tokenId and ensure the current owner is the admin
        try
            IERC721EnumerableUpgradeable(_settings.token).ownerOf(
                _settings.tokenId
            )
        returns (address nftOwner) {
            // Check if address is the admin address
            if (nftOwner != admin) {
                revert DOES_NOT_OWN_NFT();
            }
        } catch {
            revert TOKEN_BEING_OFFERED_NEEDS_TO_EXIST();
        }
    }

    /// @notice Internal function to request entropy
    function _requestRoll() internal {
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

        // Emit setup draw user event
        emit SetupDraw(msg.sender, settings);

        // Request initial roll
        _requestRoll();

        // Attempt to transfer token into this address
        try
            IERC721EnumerableUpgradeable(settings.token).transferFrom(
                msg.sender,
                address(this),
                settings.tokenId
            )
        {} catch {
            revert TOKEN_NEEDS_TO_BE_APPROVED_TO_CONTRACT();
        }

        // Return the current chainlink request id
        return request.currentChainlinkRequestId;
    }

    /// @notice Call this to re-draw the raffle
    /// @return chainlink request ID
    /// @dev Only callable by the owner
    function redraw() external onlyOwner returns (uint256) {
        if (request.drawTimelock >= block.timestamp) {
            revert TOO_SOON_TO_REDRAW();
        }

        // Reset request
        delete request;

        // Re-roll
        _requestRoll();

        // Owner of token to raffle needs to be this contract
        if (
            IERC721EnumerableUpgradeable(settings.token).ownerOf(
                settings.tokenId
            ) != address(this)
        ) {
            revert DOES_NOT_OWN_NFT();
        }

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
        // Words requested is an immutable set to 1
        if (_randomWords.length != wordsRequested) {
            revert WRONG_LENGTH_FOR_RANDOM_WORDS();
        }

        // Set request details
        request.hasChosenRandomNumber = true;

        // Get total token range
        uint256 tokenRange = settings.drawingTokenEndId -
            settings.drawingTokenStartId;

        // Store a number from it here (reduce number here to reduce gas usage)
        // We know there will only be 1 word sent at this point.
        request.currentChosenTokenId =
            (_randomWords[0] % tokenRange) +
            settings.drawingTokenStartId;

        // Emit completed event.
        emit DiceRollComplete(msg.sender, request);
    }

    /// @notice Function to determine if the user has won in the current drawing
    /// @param user address for the user to check if they have won in the current drawing
    function hasUserWon(address user) public view returns (bool) {
        if (!request.hasChosenRandomNumber) {
            revert NEEDS_TO_HAVE_CHOSEN_A_NUMBER();
        }

        return
            user ==
            IERC721EnumerableUpgradeable(settings.drawingToken).ownerOf(
                request.currentChosenTokenId
            );
    }

    /// @notice Function for the winner to call to retrieve their NFT
    function winnerClaimNFT() external {
        // Assume (potential) winner calls this fn, cache.
        address user = msg.sender;

        // Check if this user has indeed won.
        if (!hasUserWon(user)) {
            revert USER_HAS_NOT_WON();
        }

        // Emit a celebratory event
        emit WinnerSentNFT(
            user,
            address(settings.token),
            settings.tokenId,
            settings
        );

        // Transfer token to the winter.
        IERC721EnumerableUpgradeable(settings.token).transferFrom(
            address(this),
            msg.sender,
            settings.tokenId
        );
    }

    /// @notice Optional last resort admin reclaim nft function
    /// @dev Only callable by the owner
    function lastResortTimelockOwnerClaimNFT() external onlyOwner {
        // If recoverTimelock is not setup, or if not yet occurred
        if (
            settings.recoverTimelock == 0 ||
            settings.recoverTimelock > block.timestamp
        ) {
            // Stop the withdraw
            revert RECOVERY_IS_NOT_YET_POSSIBLE();
        }

        // Send event for indexing that the owner reclaimed the NFT
        emit OwnerReclaimedNFT(owner());

        // Transfer token to the admin/owner.
        IERC721EnumerableUpgradeable(settings.token).transferFrom(
            address(this),
            owner(),
            settings.tokenId
        );
    }
}
