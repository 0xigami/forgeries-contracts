// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {VRFCoordinatorV2} from "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";
import {VRFNFTRandomDraw} from "../src/VRFNFTRandomDraw.sol";
import {VRFNFTRandomDrawFactory} from "../src/VRFNFTRandomDrawFactory.sol";

import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

import {IVRFNFTRandomDraw} from "../src/interfaces/IVRFNFTRandomDraw.sol";
import {IVRFNFTRandomDrawFactory} from "../src/interfaces/IVRFNFTRandomDrawFactory.sol";
import {VRFNFTRandomDrawFactoryProxy} from "../src/VRFNFTRandomDrawFactoryProxy.sol";

import {IOwnableUpgradeable} from "../src/ownable/IOwnableUpgradeable.sol";

contract VRFNFTRandomDrawFactoryTest is Test {
    function testFactoryInitializeConstructor() public {
        address mockImplAddress = address(0x123);
        VRFNFTRandomDrawFactory factory = new VRFNFTRandomDrawFactory(
            (mockImplAddress)
        );
        vm.expectRevert();
        factory.initialize(address(0x222));
        assertEq(IOwnableUpgradeable(address(factory)).owner(), address(0x0));
    }

    function testFactoryVersion() public {
        address mockImplAddress = address(0x123);
        VRFNFTRandomDrawFactory factory = new VRFNFTRandomDrawFactory(
            (mockImplAddress)
        );
        assertEq(factory.contractVersion(), 1);
    }

    function testFactoryInitializeProxy() public {
        address mockImplAddress = address(0x123);
        address defaultOwnerAddress = address(0x222);
        VRFNFTRandomDrawFactory factory = new VRFNFTRandomDrawFactory(
            address(mockImplAddress)
        );

        VRFNFTRandomDrawFactoryProxy proxy = new VRFNFTRandomDrawFactoryProxy(
            address(factory),
            defaultOwnerAddress
        );
        assertEq(
            IOwnableUpgradeable(address(proxy)).owner(),
            defaultOwnerAddress
        );
    }
}
