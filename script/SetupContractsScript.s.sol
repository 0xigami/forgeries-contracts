// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {VRFNFTRandomDraw} from "../src/VRFNFTRandomDraw.sol";
import {VRFNFTRandomDrawFactory} from "../src/VRFNFTRandomDrawFactory.sol";
import {VRFNFTRandomDrawFactoryProxy} from "../src/VRFNFTRandomDrawFactoryProxy.sol";
import {VRFCoordinatorV2} from "@chainlink/contracts/src/v0.8/VRFCoordinatorV2.sol";

contract SetupContractsScript is Script {
    address coordinatorAddress;
    address factoryOwner;
    address proxyNewOwner;
    bytes32 keyHash;

    function setUp() public {
        coordinatorAddress = vm.envAddress("CHAINLINK_COORDINATOR");
        factoryOwner = vm.envAddress("FACTORY_OWNER");
        // can be zero to skip setting up proxy
        proxyNewOwner = vm.envOr("NEW_PROXY_WITH_OWNER", address(0));
        keyHash = vm.envBytes32("KEY_HASH");
    }

    function run() public {
        vm.startBroadcast();

        VRFNFTRandomDraw drawImpl = new VRFNFTRandomDraw(
            coordinatorAddress,
            keyHash
        );

        VRFNFTRandomDrawFactory factoryImpl = new VRFNFTRandomDrawFactory(
            address(drawImpl)
        );

        address factoryProxyAddress;
        if (proxyNewOwner != address(0)) {
            factoryProxyAddress = address(
                new VRFNFTRandomDrawFactoryProxy(
                    address(factoryImpl),
                    proxyNewOwner
                )
            );
        }

        console2.log("Factory Impl: ");
        console2.log(address(factoryImpl));
        console2.log("Draw Impl: ");
        console2.log(address(drawImpl));

        if (factoryProxyAddress != address(0)) {
            console2.log("Factory Proxy: ");
            console2.log(factoryProxyAddress);
        }
    }
}
