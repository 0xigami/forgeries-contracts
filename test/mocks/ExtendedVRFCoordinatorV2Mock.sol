// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {MockAggregator} from "@chainlink/contracts/src/v0.8/mocks/MockAggregator.sol";

contract MockAggregatorResponse {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, 60000000000000000, 0, 0, 0);
    }
}

contract ExtendedVRFCoordinatorV2Mock is VRFCoordinatorV2Mock {
    MockAggregatorResponse public LINK_ETH_FEED;
    address public LINK;

    constructor(uint96 _baseFee, uint96 _gasPriceLink, address token)
        VRFCoordinatorV2Mock(_baseFee, _gasPriceLink)
    {
        LINK_ETH_FEED = new MockAggregatorResponse();
        LINK = token;
    }
    
  function onTokenTransfer(
    address, /* sender */
    uint256 amount,
    bytes calldata data
  ) external {
    uint64 subId = abi.decode(data, (uint64));
    // We do not check that the msg.sender is the subscription owner,
    // anyone can fund a subscription.
    uint256 oldBalance = s_subscriptions[subId].balance;
    s_subscriptions[subId].balance += uint96(amount);
    // s_totalBalance += uint96(amount);
    emit SubscriptionFunded(subId, oldBalance, oldBalance + amount);
  }

}
