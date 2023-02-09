// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {VRFCoordinatorV2} from "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";
import {VRFNFTRandomDraw} from "../src/VRFNFTRandomDraw.sol";
import {VRFNFTRandomDrawFactory} from "../src/VRFNFTRandomDrawFactory.sol";

import {IOwnableUpgradeable} from "../src/ownable/IOwnableUpgradeable.sol";

import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import {IVRFNFTRandomDraw} from "../src/interfaces/IVRFNFTRandomDraw.sol";
import {IVRFNFTRandomDrawFactory} from "../src/interfaces/IVRFNFTRandomDrawFactory.sol";

import {MockNFT} from "./mocks/MockNFT.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {ExtendedVRFCoordinatorV2Mock} from "./mocks/ExtendedVRFCoordinatorV2Mock.sol";

contract VRFNFTRandomDrawTest is Test {
    MockNFT targetNFT;
    MockNFT drawingNFT;
    MockERC20 linkTokens;
    VRFNFTRandomDrawFactory factory;

    ExtendedVRFCoordinatorV2Mock mockCoordinator;

    address user = address(0x2134);
    address admin = address(0x0132);

    VRFNFTRandomDraw currentDraw;

    function setUp() public {
        vm.label(user, "USER");
        vm.label(admin, "ADMIN");

        targetNFT = new MockNFT("target", "target");
        vm.label(address(targetNFT), "TargetNFT");
        drawingNFT = new MockNFT("drawing", "drawing");
        vm.label(address(drawingNFT), "DrawingNFT");
        linkTokens = new MockERC20("link", "link");
        vm.label(address(linkTokens), "LINK");

        mockCoordinator = new ExtendedVRFCoordinatorV2Mock(
            0.05 ether,
            1000,
            address(linkTokens)
        );

        VRFNFTRandomDraw drawImpl = new VRFNFTRandomDraw(
            address(mockCoordinator),
            bytes32(
                0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
            )
        );
        // Unproxied/unowned factory
        factory = new VRFNFTRandomDrawFactory(address(drawImpl));
    }

    function _setupLinkAndNFTs(address setupUser) internal {
        vm.startPrank(setupUser);
        targetNFT.mint();

        address newRaffleAddress = factory.getNextDrawingAddress(setupUser);

        targetNFT.setApprovalForAll(newRaffleAddress, true);

        linkTokens.mint(10 ether);
        linkTokens.approve(newRaffleAddress, 10 ether);

        vm.stopPrank();
    }

    function test_Version() public {
        IVRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 2 days;
        settings.recoverBufferTime = 2 weeks;
        settings.token = address(targetNFT);
        settings.tokenId = 0;
        settings.drawingTokenStartId = 0;
        settings.drawingTokenEndId = 2;
        settings.drawingToken = address(drawingNFT);

        _setupLinkAndNFTs(user);

        vm.prank(user);
        (address drawAddress, ) = factory.makeNewDraw(settings);

        VRFNFTRandomDraw draw = VRFNFTRandomDraw(drawAddress);

        assertEq(draw.contractVersion(), 2);
    }

    function test_InvalidOptionTime() public {
        IVRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 0;
        // invalid time for drawing
        vm.expectRevert(
            IVRFNFTRandomDraw
                .REDRAW_TIMELOCK_NEEDS_TO_BE_MORE_THAN_A_DAY
                .selector
        );
        factory.makeNewDraw(settings);

        // fix this issue
        settings.drawBufferTime = 2 days;

        // recovery timelock too soon
        vm.expectRevert(
            IVRFNFTRandomDraw
                .RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK
                .selector
        );
        factory.makeNewDraw(settings);

        // fix recovery issue
        settings.recoverBufferTime = 2 weeks;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVRFNFTRandomDraw.TOKEN_NEEDS_TO_BE_A_CONTRACT.selector,
                address(0x0)
            )
        );
        factory.makeNewDraw(settings);
    }

    function test_InvalidRecoverTimelock() public {
        VRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 1 days;
        settings.recoverBufferTime = 1 days;
        // recovery timelock too soon
        vm.expectRevert(
            IVRFNFTRandomDraw
                .RECOVER_TIMELOCK_NEEDS_TO_BE_AT_LEAST_A_WEEK
                .selector
        );
        factory.makeNewDraw(settings);
    }

    function test_ZeroTokenContract() public {
        VRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 2 days;
        settings.recoverBufferTime = 4 weeks;
        // Token is not a contract
        vm.expectRevert(
            abi.encodeWithSelector(
                IVRFNFTRandomDraw.TOKEN_NEEDS_TO_BE_A_CONTRACT.selector,
                address(0x0)
            )
        );
        factory.makeNewDraw(settings);
    }

    function test_NoTokenOwner() public {
        VRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 1 days;
        settings.recoverBufferTime = 2 weeks;
        settings.token = address(targetNFT);
        settings.drawingTokenStartId = 0;
        settings.drawingTokenEndId = 4;
        settings.drawingToken = address(drawingNFT);

        // recovery timelock too soon
        vm.expectRevert(
            IVRFNFTRandomDraw.TOKEN_BEING_OFFERED_NEEDS_TO_EXIST.selector
        );
        factory.makeNewDraw(settings);
    }

    function test_BadDrawingRange() public {
        address sender = address(0x994);
        vm.startPrank(sender);
        IVRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 1 days;
        settings.recoverBufferTime = 2 weeks;
        settings.token = address(targetNFT);
        settings.drawingToken = address(drawingNFT);
        settings.tokenId = 0;
        settings.drawingTokenStartId = 2;
        targetNFT.mint();

        // recovery timelock too soon
        vm.expectRevert(IVRFNFTRandomDraw.DRAWING_TOKEN_RANGE_INVALID.selector);
        factory.makeNewDraw(settings);
    }

    function test_TokenNotApproved() public {
        address sender = address(0x994);
        IVRFNFTRandomDraw.Settings memory settings;
        settings.drawBufferTime = 1 days;
        settings.recoverBufferTime = 2 weeks;
        settings.token = address(targetNFT);
        settings.tokenId = 0;
        settings.drawingTokenStartId = 0;
        settings.drawingTokenEndId = 2;
        settings.drawingToken = address(drawingNFT);

        vm.prank(sender);
        targetNFT.mint();

        vm.prank(sender);
        vm.expectRevert("ERC721: caller is not token owner or approved");
        factory.makeNewDraw(settings);
    }

    function test_CannotRerollInFlight() public {
        address winner = address(0x1337);
        vm.label(winner, "winner");

        _setupLinkAndNFTs(winner);

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }

        (address consumerAddress, ) = factory.makeNewDraw(
            IVRFNFTRandomDraw.Settings({
                token: address(targetNFT),
                tokenId: 0,
                drawingToken: address(drawingNFT),
                drawingTokenStartId: 0,
                drawingTokenEndId: 10,
                drawBufferTime: 1 days,
                recoverBufferTime: 2 weeks
            })
        );
        vm.label(consumerAddress, "drawing instance");

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        vm.expectRevert(IVRFNFTRandomDraw.TOO_SOON_TO_REDRAW.selector);
        drawing.redraw();

        vm.warp(block.timestamp + 10 days);

        vm.expectRevert(IVRFNFTRandomDraw.REQUEST_IN_FLIGHT.selector);
        drawing.redraw();

        vm.stopPrank();
    }

    function test_ValidateRequestID() public {
        address winner = address(0x1337);
        vm.label(winner, "winner");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        _setupLinkAndNFTs(admin);

        vm.startPrank(admin);

        (address consumerAddress, uint256 requestId) = factory.makeNewDraw(
            IVRFNFTRandomDraw.Settings({
                token: address(targetNFT),
                tokenId: 0,
                drawingToken: address(drawingNFT),
                drawingTokenStartId: 0,
                drawingTokenEndId: 10,
                drawBufferTime: 1 days,
                recoverBufferTime: 2 weeks
            })
        );
        vm.label(consumerAddress, "drawing instance");

        vm.stopPrank();
        vm.prank(consumerAddress);
        uint64 subId = IVRFNFTRandomDraw(consumerAddress).subscriptionId();

        vm.prank(admin);
        linkTokens.mint(10 ether);

        vm.prank(admin);
        linkTokens.transferAndCall(
            address(mockCoordinator),
            10 ether,
            abi.encode(subId)
        );

        vm.prank(consumerAddress);
        uint256 otherRequestId = VRFCoordinatorV2(address(mockCoordinator))
            .requestRandomWords({
                keyHash: bytes32(
                    0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
                ),
                subId: subId,
                requestConfirmations: uint16(1),
                callbackGasLimit: 100000,
                numWords: 3
            });

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        vm.prank(address(drawing));
        mockCoordinator.fulfillRandomWords(otherRequestId, consumerAddress);
        (uint256 requestIdResponse, bool hasChosenNumber, ) = drawing
            .getRequestDetails();
        assert(!hasChosenNumber);

        mockCoordinator.fulfillRandomWords(requestId, consumerAddress);
        (requestIdResponse, hasChosenNumber, ) = drawing.getRequestDetails();
        assert(hasChosenNumber);

        assertTrue(drawing.hasUserWon(winner));
    }

    function test_FullDrawing() public {
        address winner = address(0x1337);
        vm.label(winner, "winner");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        _setupLinkAndNFTs(admin);

        vm.startPrank(admin);
        (address consumerAddress, uint256 drawingId) = factory.makeNewDraw(
            IVRFNFTRandomDraw.Settings({
                token: address(targetNFT),
                tokenId: 0,
                drawingToken: address(drawingNFT),
                drawingTokenStartId: 0,
                drawingTokenEndId: 10,
                drawBufferTime: 1 days,
                recoverBufferTime: 2 weeks
            })
        );
        vm.label(consumerAddress, "drawing instance");

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        targetNFT.setApprovalForAll(consumerAddress, true);

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
        address winner = address(0x1337);
        vm.label(winner, "winner");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        _setupLinkAndNFTs(admin);

        vm.startPrank(admin);
        (address consumerAddress, uint256 drawingId) = factory.makeNewDraw(
            IVRFNFTRandomDraw.Settings({
                token: address(targetNFT),
                tokenId: 0,
                drawingToken: address(drawingNFT),
                drawingTokenStartId: 0,
                drawingTokenEndId: 10,
                drawBufferTime: 1 days,
                recoverBufferTime: 2 weeks
            })
        );
        vm.label(consumerAddress, "drawing instance");

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        targetNFT.setApprovalForAll(consumerAddress, true);

        mockCoordinator.fulfillRandomWords(drawingId, consumerAddress);

        (, , uint256 drawTimelock) = drawing.getRequestDetails();
        assertEq(drawTimelock, 86401);
        assertEq(block.timestamp, 1);

        vm.expectRevert(IVRFNFTRandomDraw.TOO_SOON_TO_REDRAW.selector);
        drawing.redraw();

        vm.warp(2 days);

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

    function test_LoserCannotWithdraw() public {
        address winner = address(0x1337);
        vm.label(winner, "winner");

        address loser = address(0x019);
        vm.label(loser, "loser");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        vm.startPrank(loser);
        for (uint256 tokensCount = 0; tokensCount < 80; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        _setupLinkAndNFTs(admin);

        vm.prank(admin);
        (address consumerAddress, uint256 drawingId) = factory.makeNewDraw(
            IVRFNFTRandomDraw.Settings({
                token: address(targetNFT),
                tokenId: 0,
                drawingToken: address(drawingNFT),
                drawingTokenStartId: 0,
                drawingTokenEndId: 10,
                drawBufferTime: 1 days,
                recoverBufferTime: 2 weeks
            })
        );
        vm.label(consumerAddress, "drawing instance");

        VRFNFTRandomDraw drawing = VRFNFTRandomDraw(consumerAddress);

        vm.prank(loser);
        vm.expectRevert(
            IVRFNFTRandomDraw.NEEDS_TO_HAVE_CHOSEN_A_NUMBER.selector
        );
        drawing.winnerClaimNFT();

        vm.prank(admin);
        targetNFT.setApprovalForAll(consumerAddress, true);

        vm.prank(loser);
        vm.expectRevert();
        drawing.winnerClaimNFT();

        mockCoordinator.fulfillRandomWords(drawingId, consumerAddress);

        vm.prank(loser);
        vm.expectRevert();
        drawing.winnerClaimNFT();

        vm.prank(winner);
        drawing.winnerClaimNFT();

        assertEq(targetNFT.balanceOf(admin), 0);
        assertEq(targetNFT.balanceOf(winner), 1);

        vm.prank(loser);
        vm.expectRevert(IOwnableUpgradeable.ONLY_OWNER.selector);
        drawing.lastResortTimelockOwnerClaimNFT();

        // should be able to call nft
        assertEq(targetNFT.balanceOf(admin), 0);
        assertEq(targetNFT.balanceOf(winner), 1);
    }

    function test_NFTNotApproved() public {
        address winner = address(0x1337);
        vm.label(winner, "winner");

        vm.startPrank(winner);
        for (uint256 tokensCount = 0; tokensCount < 10; tokensCount++) {
            drawingNFT.mint();
        }
        vm.stopPrank();

        vm.startPrank(admin);
        targetNFT.mint();

        vm.expectRevert();
        (address consumerAddress, ) = factory.makeNewDraw(
            IVRFNFTRandomDraw.Settings({
                token: address(targetNFT),
                tokenId: 0,
                drawingToken: address(drawingNFT),
                drawingTokenStartId: 0,
                drawingTokenEndId: 10,
                drawBufferTime: 1 days,
                recoverBufferTime: 2 weeks
            })
        );
    }
}
