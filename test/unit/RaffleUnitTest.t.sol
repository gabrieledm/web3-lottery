// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffleScript} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";

contract RaffleUnitTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    // Creates an address derived from the provided name
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    uint256 public constant LINK_BALANCE = 100 ether;

    uint256 private entranceFee;
    uint256 private interval;
    address private vrfCoordinator;
    bytes32 private gasLane;
    uint256 private subscriptionId;
    uint32 private callbackGasLimit;
    LinkToken private link;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffleScript deployRaffleScript = new DeployRaffleScript();
        (raffle, helperConfig) = deployRaffleScript.run();
        // Sets an address' balance
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        entranceFee = networkConfig.entranceFee;
        interval = networkConfig.interval;
        vrfCoordinator = networkConfig.vrfCoordinator;
        gasLane = networkConfig.gasLane;
        subscriptionId = networkConfig.subscriptionId;
        callbackGasLimit = networkConfig.callbackGasLimit;
        link = LinkToken(networkConfig.link);

        vm.startPrank(msg.sender);
        if (block.chainid == LOCAL_CHAIN_ID) {
            link.mint(msg.sender, LINK_BALANCE);
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, LINK_BALANCE);
        }
        link.approve(vrfCoordinator, LINK_BALANCE);
        vm.stopPrank();
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Sets block.timestamp
        // Simulate has passed the interval to pass the checkUpkeep
        vm.warp(block.timestamp + interval + 1);
        // Sets block.height
        vm.roll(block.number + 1);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         INITIAL STATE
    //////////////////////////////////////////////////////////////*/
    function test_initialState_RaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /*//////////////////////////////////////////////////////////////
                          ENTER RAFFLE
    //////////////////////////////////////////////////////////////*/
    function test_enterRaffle_RaffleRevertWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        // Expect revert for a specific error
        vm.expectRevert(Raffle.Raffle__NotEnoughETH.selector);
        raffle.enterRaffle();
    }

    function test_enterRaffle_RaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function test_enterRaffle_EnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER);

        // Expect an Event is emitted by checking
        // - The first indexed parameter
        // - The address of emitter
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    function test_enterRaffle_dontAllowPlayersToEnterWhileRaffleIsCalculating() public raffleEntered {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                              CHECK UPKEEP
    //////////////////////////////////////////////////////////////*/
    function test_checkUpkeepReturnsFalseIfItHasNoBalance() public {
        // Sets block.timestamp
        // Simulate has passed the interval to pass the checkUpkeep
        vm.warp(block.timestamp + interval + 1);
        // Sets block.height
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function test_checkUpkeepReturnsFalseIfRaffleIsNotOpen() public raffleEntered {
        raffle.performUpkeep("");

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(!upkeepNeeded);
    }

    function test_checkUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function test_checkUpkeepReturnsTrueWhenParametersAreGood() public raffleEntered {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                             PERFORM UPKEEP
    //////////////////////////////////////////////////////////////*/
    function test_performUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEntered {
        // If this fails, then the test will fail
        raffle.performUpkeep("");
    }

    function test_performUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 players = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance += entranceFee;
        players = 1;

        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, players, raffleState)
        );
        raffle.performUpkeep("");
    }

    function test_performUpkeepUpdatedRaffleStateAndEmitsRequestId() public raffleEntered {
        // Record all the transaction logs
        vm.recordLogs();

        raffle.performUpkeep("");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Get the log at index 1 because the one at index 0 is emitted by the VRFCoordinatorV2_5 itself
        bytes32 requestId = logs[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /*//////////////////////////////////////////////////////////////
                          FULFILL RANDOM WORDS
    //////////////////////////////////////////////////////////////*/
    /**
     * If the chain is not the development one, skip the test
     */
    modifier skipMockForFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }
    /**
     * @dev Fuzz test
     * @param randomRequestId - A random parameter injected during the test
     */

    function test_fulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        skipMockForFork
        raffleEntered
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function test_fulfillRandomWordsPicksWinnerAndSendsMoney() public skipMockForFork raffleEntered {
        uint256 additionalPlayers = 3;
        uint256 startIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startIndex; i < startIndex + additionalPlayers; i++) {
            // Convert a number to an address
            address newPlayer = address(uint160(i));
            // Setup a prank from an address that has some ether
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Get the log at index 1 because the one at index 0 is emitted by the VRFCoordinatorV2_5 itself
        bytes32 requestId = logs[1].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalPlayers + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
