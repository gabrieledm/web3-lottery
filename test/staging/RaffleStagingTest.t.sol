// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {DeployRaffleScript} from "script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleIntegrationTest is Test, CodeConstants {
    /* Errors */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    Raffle private raffle;
    HelperConfig private helperConfig;

    uint256 private subscriptionId;
    bytes32 private gasLane;
    uint256 private interval;
    uint256 private entranceFee;
    uint32 private callbackGasLimit;
    address private vrfCoordinator;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffleScript deployer = new DeployRaffleScript();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        subscriptionId = config.subscriptionId;
        gasLane = config.gasLane;
        interval = config.interval;
        entranceFee = config.entranceFee;
        callbackGasLimit = config.callbackGasLimit;
        vrfCoordinator = config.vrfCoordinator;
    }

    /////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier onlyOnDeployedContracts() {
        if (block.chainid == LOCAL_CHAIN_ID) {
            return;
        }
        // Returns the identifier for the currently active fork.
        // Reverts if no fork is currently active.
        try vm.activeFork() returns (uint256) {
            return;
        } catch {
            _;
        }
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public raffleEntered onlyOnDeployedContracts {
        // Arrange
        // Act / Assert
        vm.expectRevert("nonexistent request");
        // vm.mockCall could be used here...
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(0, address(raffle));

        vm.expectRevert("nonexistent request");

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered onlyOnDeployedContracts {
        address expectedWinner = address(1);

        // Arrange
        uint256 additionalEntrances = 3;
        uint256 startingIndex = 1; // We have starting index be 1 so we can start with address(1) and not address(0)

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether); // deal 1 eth to the player
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }

}
