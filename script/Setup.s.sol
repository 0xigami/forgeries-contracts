// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {VRFNFTRandomDraw} from "../src/VRFNFTRandomDraw.sol";
import {VRFNFTRandomDrawFactory} from "../src/VRFNFTRandomDrawFactory.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";

contract SetupContractsScript is Script {
    address coordinatorAddress;

    function setUp() public {
        coordinatorAddress = vm.envAddress("CHAINLINK_COORDINATOR");
    }

    function run() public {
        vm.broadcast();
        VRFNFTRandomDraw drawImpl = new VRFNFTRandomDraw(VRFCoordinatorV2Interface(coordinatorAddress));
        VRFNFTRandomDrawFactory factory = new VRFNFTRandomDrawFactory(
            address(drawImpl)
        );

        console2.log("Factory: ");
        console2.log(address(factory));
        console2.log("Draw Impl: ");
        console2.log(address(drawImpl));
        vm.stopBroadcast();
        vm.label(address(factory), "factory");
    }
}
