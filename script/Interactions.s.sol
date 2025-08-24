// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract CreateSubscriptionScript is Script {
    function run() external returns (uint256, address) {
        return createSubscriptionUsingConfig();
    }

    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;

        return createSubscription(vrfCoordinator, account);
    }

    function createSubscription(address vrfCoordinator, address account) public returns (uint256, address) {
        console.log("---------- createSubscription ----------");
        console.log("Creating subscription on chain id", block.chainid);

        vm.startBroadcast(account);

        // Programmatically create new VRF Subscription
        uint256 subscriptionId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();

        vm.stopBroadcast();

        console.log("Created Subscription", subscriptionId);
        console.log("---------- createSubscription ----------");
        return (subscriptionId, vrfCoordinator);
    }
}

contract FundSubscriptionScript is CodeConstants, Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function run() external {
        fundSubscriptionUsingConfig();
    }

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;

        if (subscriptionId == 0) {
            CreateSubscriptionScript createSubscriptionScript = new CreateSubscriptionScript();
            (uint256 updatedSubId, address updatedVRFv2) = createSubscriptionScript.run();
            subscriptionId = updatedSubId;
            vrfCoordinator = updatedVRFv2;
            console.log("New SubId Created! ", subscriptionId, "VRF Address: ", vrfCoordinator);
        }

        fundSubscription(vrfCoordinator, subscriptionId, linkToken, account);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address linkToken, address account)
        public
    {
        console.log("---------- fundSubscription ----------");
        console.log("Funding subscription", subscriptionId);
        console.log("Using vrfCoordinator", vrfCoordinator);
        console.log("On ChainId", block.chainid);

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast(account);

            // Programmatically send LINK token to the VRF Subscription
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT);

            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);

            LinkToken(linkToken).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));

            vm.stopBroadcast();
        }
        console.log("---------- fundSubscription ----------");
    }
}

contract AddConsumerScript is Script {
    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(mostRecentlyDeployed);
    }

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subscriptionId, account);
    }

    function addConsumer(address contractToAddToVrf, address vrfCoordinator, uint256 subscriptionId, address account)
        public
    {
        console.log("---------- addConsumer ----------");

        console.log("Adding consumer contract", contractToAddToVrf);
        console.log("To VRF Coordinator", vrfCoordinator);
        console.log("On ChainId", block.chainid);

        vm.startBroadcast(account);

        // Programmatically register new consumer the VRF Subscription
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subscriptionId, contractToAddToVrf);

        vm.stopBroadcast();
        console.log("---------- addConsumer ----------");
    }
}
