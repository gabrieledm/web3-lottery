// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title A sample Raffle contract
 * @author Gabriele Del Monte
 * @notice This contract is for creating a sample raffle
 * @dev Implements ChainLink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /* Type declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1

    }

    /* State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState public s_raffleState;

    /* Events */
    /**
     * @dev Events - The Events aren't accessibile by SmartContract.
     *      This is why they are cheaper.
     * @dev Indexed - The indexed parameters are more efficient to be used to search for specific events.
     *      Allow to search for these events using the indexed parameters as filters.
     */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    /* Errors */
    /**
     * @dev Best practice: <contract-name>__<error-name>
     */
    error Raffle__NotEnoughETH();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        //        require(msg.value >= i_entranceFee, Raffle__NotEnoughETH());
        /**
         * @dev Gas optimization: Usage of custom error
         */
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETH();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @notice Function from ChainLink's AutomationCompatibleInterface (https://docs.chain.link/chainlink-automation/guides/compatible-contracts)
     * @dev This is the function that ChainLink nodes will call to see if the lottery is ready to pick a winner.
     * @return upkeepNeeded - true if
     *     - The time interval has passed between raffle runs
     *     - The lottery is open
     *     - The contract has ETH
     *     - Implicitly, your subscription has enough LINK
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        // Define the logic if is the time to pick a winner for the raffle
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasEth = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        // This way the upkeepNeeded defined in returns statement will be updated
        // We can avoid to explicitly use the return statement
        upkeepNeeded = (timeHasPassed && isOpen && hasEth && hasPlayers);

        return (upkeepNeeded, "0x0");
    }

    /**
     * @notice Function from ChainLink's AutomationCompatibleInterface (https://docs.chain.link/chainlink-automation/guides/compatible-contracts)
     */
    function performUpkeep(bytes calldata /* performData */ ) external override {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        // Use ChainLink VRF: https://docs.chain.link/vrf
        // 1 - Request a RNG (Random number generator) (https://docs.chain.link/vrf/v2-5/getting-started#contract-variables)
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    /**
     * @notice fulfillRandomWords handles the VRF response. Your contract must implement it.
     *
     * @dev VRFConsumerBaseV2Plus expects its subcontracts to have a method with this
     * @dev signature, and will call it once it has verified the proof
     * @dev associated with the randomness. (It is triggered via a call to rawFulfillRandomWords)
     * @dev Implements fulfillRandomWords from VRFConsumerBaseV2Plus contract
     *
     * @param randomWords the VRF output expanded to the requested number of words
     */
    // * @param requestId The Id initially returned by requestRandomWords
    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        // 2 - Get a RNG (Random number generator)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        // Reset the players array
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);

        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Functions
     */
    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
