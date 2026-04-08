// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

enum RaffleEndCondition {
    NUMBER_MINTED,
    DURATION
}

struct L2RaffleSettings {
    address raffle721Contract;
    uint256 targetNFTContract;
    RaffleEndCondition endCondition;
    uint256 toWinTokenId;
    uint256 raffleNumberMinted;
    uint256 raffleDuration;
    uint256 recoveryPeriod;
}

contract L2Raffle is OwnableUpgradeable, ERC721Token, IERC721Receiver, I1155Receiver {
    error InvalidInitializationSettings();
    error RecoveryPeriodTooShort();
    error RaffleIsTooSmall();
    error CallFailed(bytes reason);
    error CanOnlyBeSetupOnce();
    error RaffleAlreadyStarted();
    error RaffleHasNotStarted();

    /// @notice 0 if raffle has not started
    uint256 public raffleStarted;
    /// @notice set when a token is received
    uint256 public receivedTokenAt;

    L2RaffleSettings public raffleSettings;

    uint256 immutable defaultUnclaimedTokenWithdrawPeriod;
    uint256 immutable minRaffleSize;

    constructor(
        uint256 defaultUnclaimedTokenWithdrawPeriod_,
        uint256 minRaffleSize_
    ) initializer {
        unclaimedTokenWithdrawPeriod = defaultUnclaimedTokenWithdrawPeriod_;
        minRaffleSize = minRaffleSize_;
    }

    function receiveToken() public {
        if (receivedTokenAt > 0) {
            revert CanOnlyBeSetupOnce();
        }
        receivedTokenAt = block.timestamp;
    }

    function isOver() public view returns (bool) {
        if (raffleStarted == 0) {
            revert RaffleHasNotStarted();
        }

        if (raffleSettings.endCondition == RaffleEndCondition.NUMBER_MINTED) {
            (, uint256 maxSupply, uint256 totalMinted) = IZoraEdition(
                raffleSettings.targetContract
            ).getTokenInfo(raffleSettings.raffleTokenId);
            if (maxSupply == totalMinted) {
                return true;
            }
            return false;
        } else if (raffleSettings.endCondition == RaffleEndCondition.DURATION) {
            return (block.timestamp >
                raffleStarted + raffleSettings.raffleDuration);
        }
    }

    function setupRaffle(L2RaffleSettings raffleSettings) {
        if (raffleStarted > 0) {
            revert RaffleAlreadyStarted();
        }

        if (raffleSettings.targetNFTContract)
            if (
                IERC1155(raffleSettings.targetContract).balanceOf(
                    toWinTokenId,
                    address(this)
                ) > 0
            ) // Ensure this contract owns the target
            {
                revert InvalidInitalizationSettings();
            }

        if (raffleSettings.recoveryPeriod < 7 days) {
            revert RecoveryPeriodTooShort();
        }

        if (raffleSettings.rafflePeriod < 1 days) {
            revert RafflePeriodTooShort();
        }

        if (maxSupply < minRaffleSize) {
            revert RaffleIsTooSmall();
        }

        // Ensure raffle token exists by calling uri. If URI fails, by the standard the token does not exist.
        IERC1155(raffleSettings.targetContract).uri(
            raffleSettings.raffleTokenId
        );

        raffleStarted = block.timestamp;
    }

    function determineAndSendWinner() {}

    function winnerWithdraw() public {}

    function getRaffleSettings() public view returns (RaffleSettings memory) {
        return raffleSettings;
    }

    function recoverTokensAfterTokenPeriod(address target, bytes memory data) {
        if (raffleStarted > 0) {
            if (
                block.timestamp < raffleStarted + raffleSettings.recoveryPeriod
            ) {
                revert RecoveryPeriodTooEarly();
            }
            (bytes memory reason, bool success) = target.call(data);
            if (!success) {
                revert CallFailed(reason);
            }
            return;
        }
        if (
            receivedTokenAt > 0 &&
            block.timestamp >=
            defaultUnclaimedTokenWithdrawPeriod + receivedTokenAt
        ) {
            (bytes memory reason, bool success) = target.call(data);
            if (!success) {
                revert CallFailed(reason);
            }
            return;
        }
        revert ContractInvalidInitalizationState();
    }
}
