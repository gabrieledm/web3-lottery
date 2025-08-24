// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscriptionScript, FundSubscriptionScript, AddConsumerScript} from "./Interactions.s.sol";

contract DeployRaffleScript is Script {
    function run() external returns (Raffle, HelperConfig) {
        return deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        AddConsumerScript addConsumerScript = new AddConsumerScript();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        if (networkConfig.subscriptionId == 0) {
            // Create new VRF subscription
            CreateSubscriptionScript createSubscriptionScript = new CreateSubscriptionScript();
            // Save the returned values from createSubscription to the NetworkConfig struct
            (networkConfig.subscriptionId, networkConfig.vrfCoordinator) =
                createSubscriptionScript.createSubscription(networkConfig.vrfCoordinator, networkConfig.account);

            // Fund the newly created VRF subscription
            FundSubscriptionScript fundSubscriptionScript = new FundSubscriptionScript();
            fundSubscriptionScript.fundSubscription(
                networkConfig.vrfCoordinator, networkConfig.subscriptionId, networkConfig.link, networkConfig.account
            );

            helperConfig.setConfig(block.chainid, networkConfig);
        }

        vm.startBroadcast(networkConfig.account);
        Raffle raffle = new Raffle(
            networkConfig.entranceFee,
            networkConfig.interval,
            networkConfig.vrfCoordinator,
            networkConfig.gasLane,
            networkConfig.subscriptionId,
            networkConfig.callbackGasLimit
        );
        vm.stopBroadcast();

        addConsumerScript.addConsumer(
            address(raffle), networkConfig.vrfCoordinator, networkConfig.subscriptionId, networkConfig.account
        );

        return (raffle, helperConfig);
    }
}
