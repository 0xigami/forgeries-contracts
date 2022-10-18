// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {VRFNFTRandomDraw} from "../src/VRFNFTRandomDraw.sol";
import {VRFNFTRandomDrawFactory} from "../src/VRFNFTRandomDrawFactory.sol";

import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import {MockNFT} from "./MockNFT.sol";
import {MockERC20} from "./MockERC20.sol";

contract VRFNFTRandomDrawTest is Test {
    MockNFT targetNFT;
    MockNFT drawingNFT;
    MockERC20 linkTokens;
    VRFNFTRandomDrawFactory factory;

    VRFCoordinatorV2Mock mockCoordinator;

    address user = address(0x2134);
    address admin = address(0x0132);

    uint64 subscriptionId;

    VRFNFTRandomDraw currentDraw;

    function setupDrawing() public {
        vm.label(user, "USER");
        vm.label(admin, "ADMIN");

        subscriptionId = 1337;

        targetNFT = new MockNFT("target", "target");
        vm.label(address(targetNFT), "TargetNFT");
        drawingNFT = new MockNFT("drawing", "drawing");
        vm.label(address(drawingNFT), "DrawingNFT");
        linkTokens = new MockERC20("link", "link");
        vm.label(address(linkTokens), "LINK");

        mockCoordinator = new VRFCoordinatorV2Mock(0.1 ether, 1000);

        VRFNFTRandomDraw drawImpl = new VRFNFTRandomDraw(mockCoordinator);
        factory = new VRFNFTRandomDrawFactory(address(drawImpl));

        vm.prank(admin);
        subscriptionId = mockCoordinator.createSubscription();
    }

    function test_FullDrawing() public {
        setupDrawing();

        address winner = address(0x1337);
        vm.label(winner, "winner");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        vm.startPrank(admin);
        targetNFT.mint();

        address consumerAddress = factory.makeNewDraw(
            VRFNFTRandomDraw.Settings({
                token: IERC721EnumerableUpgradeable(address(targetNFT)),
                tokenId: 0,
                drawingToken: IERC721EnumerableUpgradeable(address(drawingNFT)),
                drawingTokenStartId: 0,
                drawBufferTime: 1 hours,
                recoverTimelock: 2 weeks,
                numberTokens: 10,
                keyHash: bytes32(
                    0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
                ),
                subscriptionId: subscriptionId
            })
        );
        vm.label(consumerAddress, "drawing instance");

        mockCoordinator.addConsumer(subscriptionId, consumerAddress);
        mockCoordinator.fundSubscription(subscriptionId, 100 ether);

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        targetNFT.setApprovalForAll(consumerAddress, true);

        uint256 drawingId = drawing.startDraw();

        mockCoordinator.fulfillRandomWords(drawingId, consumerAddress);

        vm.stopPrank();

        assertEq(targetNFT.balanceOf(winner), 0);
        assertEq(targetNFT.balanceOf(consumerAddress), 1);

        // should be able to call nft
        vm.prank(winner);
        drawing.winnerClaimNFT();
        assertEq(targetNFT.balanceOf(winner), 1);
        assertEq(targetNFT.balanceOf(consumerAddress), 0);
    }

    function test_DrawingUserCheck() public {
        setupDrawing();

        address winner = address(0x1337);
        vm.label(winner, "winner");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        vm.startPrank(admin);
        targetNFT.mint();

        address consumerAddress = factory.makeNewDraw(
            VRFNFTRandomDraw.Settings({
                token: IERC721EnumerableUpgradeable(address(targetNFT)),
                tokenId: 0,
                drawingToken: IERC721EnumerableUpgradeable(address(drawingNFT)),
                drawingTokenStartId: 0,
                drawBufferTime: 1 hours,
                recoverTimelock: 2 weeks,
                numberTokens: 10,
                keyHash: bytes32(
                    0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
                ),
                subscriptionId: subscriptionId
            })
        );
        vm.label(consumerAddress, "drawing instance");

        mockCoordinator.addConsumer(subscriptionId, consumerAddress);
        mockCoordinator.fundSubscription(subscriptionId, 100 ether);

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        targetNFT.setApprovalForAll(consumerAddress, true);

        uint256 drawingId = drawing.startDraw();

        mockCoordinator.fulfillRandomWords(drawingId, consumerAddress);

        (, , , uint256 drawTimelock) = drawing.request();
        assertEq(drawTimelock, 3601);
        assertEq(block.timestamp, 1);

        vm.expectRevert(VRFNFTRandomDraw.TOO_SOON_TO_REDRAW.selector);
        drawing.redraw();

        vm.warp(2 hours);

        drawingId = drawing.redraw();

        mockCoordinator.fulfillRandomWords(drawingId, consumerAddress);

        vm.warp(30 days);

        assertEq(targetNFT.balanceOf(admin), 0);
        assertEq(targetNFT.balanceOf(consumerAddress), 1);

        drawing.lastResortTimelockOwnerClaimNFT();

        // should be able to call nft
        assertEq(targetNFT.balanceOf(admin), 1);
        assertEq(targetNFT.balanceOf(consumerAddress), 0);
    }
}
