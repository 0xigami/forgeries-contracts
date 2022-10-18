// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";

contract VRFNFTRandomDraw is VRFConsumerBaseV2, OwnableUpgradeable {
    VRFCoordinatorV2Interface immutable coordinator;

    struct Settings {
        IERC721EnumerableUpgradeable token;
        uint256 tokenId;
        uint256 numberApplicants;
        uint256 drawTimelock;
        uint256 drawBufferTime;
        uint256 numberTokens;
        uint256 recoverTimelock;
        bytes32 keyHash;
        uint64 subscriptionId;
    }

    Settings public settings;

    struct CurrentRequest {
        uint256 currentChainlinkRequestId;
        uint256 currentChosenRandomNumber;
        bool hasChosenRandomNumber;
    }
    CurrentRequest public request;

    uint32 constant callbackGasLimit = 100_000;
    uint16 constant requestConfirmations = 3;

    error STILL_IN_WAITING_PERIOD_BEFORE_REDRAWING();
    error WITHDRAW_TIMELOCK_NEEDS_TO_BE_IN_FUTURE();
    error TOKEN_BEING_OFFERED_NEEDS_TO_EXIST();
    error TOKEN_CANNOT_BE_ZERO_ADDRESS();
    error TOKEN_NEEDS_TO_BE_APPROVED_TO_CONTRACT();
    error REQUEST_IN_FLIGHT();
    error REQUEST_DOES_NOT_MATCH_CURRENT_ID();
    error SUPPLY_TOKENS_COUNT_WRONG();
    error NEEDS_TO_HAVE_CHOSEN_A_NUMBER();
    error OWNER_RECLAIMED_UNCLAIMED_NFT();

    error WITHDRAW_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_DAY();
    error RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK();
    error USER_HAS_NOT_WON();
    error TOO_SOON_TO_REDRAW();
    error DO_NOT_OWN_NFT();
    error RECOVERY_IS_NOT_YET_POSSIBLE();
    error WRONG_LENGTH_FOR_RANDOM_WORDS();

    event InitializedDraw(address indexed sender, Settings settings);
    event SetupDraw(address indexed sender, Settings settings);
    event OwnerReclaimedNFT(address indexed owner);
    event DiceRollComplete(address indexed sender, CurrentRequest request);
    event WinnerSentNFT(
        address indexed winner,
        address indexed nft,
        uint256 indexed tokenId,
        Settings settings
    );

    constructor(VRFCoordinatorV2Interface _coordinator)
        VRFConsumerBaseV2(address(_coordinator))
    {
        coordinator = _coordinator;
    }

    function initialize(Settings memory _settings) public initializer {
        // Set new settings
        settings = _settings;

        // Check values in memory:
        if (_settings.drawTimelock < 3600 * 24) {
            revert WITHDRAW_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_DAY();
        }

        if (_settings.recoverTimelock != 0) {
            if (_settings.recoverTimelock < block.timestamp + 3600 * 24 * 7) {
                revert RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK();
            }

            settings.recoverTimelock = _settings.recoverTimelock;
        }

        if (address(_settings.token) == address(0x0)) {
            revert TOKEN_CANNOT_BE_ZERO_ADDRESS();
        }

        try _settings.token.ownerOf(_settings.tokenId) returns (
            address
        ) {} catch {
            revert TOKEN_BEING_OFFERED_NEEDS_TO_EXIST();
        }

        try _settings.token.totalSupply() returns (uint256 supply) {
            if (supply != _settings.numberTokens) {
                revert SUPPLY_TOKENS_COUNT_WRONG();
            }
        } catch {
            // If not supported, user will verify count.
        }

        __Ownable_init();

        emit InitializedDraw(msg.sender, settings);
    }

    function _requestRoll() internal {
        if (settings.token.ownerOf(settings.tokenId) != address(this)) {
            revert DO_NOT_OWN_NFT();
        }

        if (request.currentChainlinkRequestId != 0) {
            revert REQUEST_IN_FLIGHT();
        }

        if (
            request.hasChosenRandomNumber &&
            // Draw timelock not yet used
            settings.drawTimelock != 0 &&
            settings.drawTimelock < block.timestamp
        ) {
            revert STILL_IN_WAITING_PERIOD_BEFORE_REDRAWING();
        }

        // Setup re-draw timelock
        settings.drawTimelock = block.timestamp + settings.drawBufferTime;

        // Request first random round
        request.currentChainlinkRequestId = coordinator.requestRandomWords({
            keyHash: settings.keyHash,
            subId: settings.subscriptionId,
            minimumRequestConfirmations: 5,
            callbackGasLimit: callbackGasLimit,
            numWords: 1
        });
    }

    function startDraw() external onlyOwner {
        try
            settings.token.transferFrom(
                msg.sender,
                address(this),
                settings.tokenId
            )
        {} catch {
            revert TOKEN_NEEDS_TO_BE_APPROVED_TO_CONTRACT();
        }

        emit SetupDraw(msg.sender, settings);

        _requestRoll();
    }

    function redraw() external onlyOwner {
        if (settings.drawTimelock < block.timestamp) {
            revert TOO_SOON_TO_REDRAW();
        }

        // Reset request
        delete request;

        _requestRoll();
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        if (_requestId != request.currentChainlinkRequestId) {
            revert REQUEST_DOES_NOT_MATCH_CURRENT_ID();
        }

        if (_randomWords.length != 1) {
            revert WRONG_LENGTH_FOR_RANDOM_WORDS();
        }

        request.hasChosenRandomNumber = true;
        request.currentChosenRandomNumber =
            _randomWords[0] %
            settings.numberTokens;

        emit DiceRollComplete(msg.sender, request);
    }

    function winnerClaimNFT() external {
        address user = msg.sender;

        if (!hasUserWon(user)) {
            revert USER_HAS_NOT_WON();
        }

        settings.token.transferFrom(
            address(this),
            msg.sender,
            settings.tokenId
        );

        emit WinnerSentNFT(
            user,
            address(settings.token),
            settings.tokenId,
            settings
        );
    }

    function hasUserWon(address user) public view returns (bool) {
        if (!request.hasChosenRandomNumber) {
            revert NEEDS_TO_HAVE_CHOSEN_A_NUMBER();
        }

        return
            user == settings.token.ownerOf(request.currentChosenRandomNumber);
    }

    function lastResortTimelockOwnerClaimNFT() external onlyOwner {
        if (
            settings.recoverTimelock == 0 ||
            settings.recoverTimelock < block.timestamp
        ) {
            revert RECOVERY_IS_NOT_YET_POSSIBLE();
        }

        settings.token.transferFrom(address(this), owner(), settings.tokenId);

        emit OwnerReclaimedNFT(owner());
    }
}
