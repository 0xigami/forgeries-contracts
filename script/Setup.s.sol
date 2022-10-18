// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {VRFNFTRandomDraw} from "../src/VRFNFTRandomDraw.sol";
import {VRFNFTRandomDrawFactory} from "../src/VRFNFTRandomDrawFactory.sol";

contract CounterScript is Script {
    address coordinatorAddress;

    function setUp() public {
        coordinatorAddress = vm.envAddress("CHAINLINK_COORDINATOR");
    }

    function run() public {
        vm.broadcast();
        VRFNFTRandomDraw drawImpl = VRFNFTRandomDraw(coordinatorAddress);
        VRFNFTRandomDrawFactory factory = VRFNFTRandomDrawFactory(
            address(drawImpl)
        );

        vm.stopBroadcast();
        vm.label(address(factory), "factory");
    }
}
