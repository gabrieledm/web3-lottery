// SPDX-License-Identifier: MIT

// Use all Solidity versions from 0.8.19 ahead
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {CommonBase} from "forge-std/Base.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /* VRFCoordinatorV2_5Mock values */
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    // LINK/ETH price
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;

    address public FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, CommonBase, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        // Sepolia
        networkConfigs[SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 0.01 ether, //1e16
            interval: 30, // 30 seconds
            // https://docs.chain.link/vrf/v2-5/supported-networks#sepolia-testnet
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            // subscriptionId created from the UI at https://vrf.chain.link/
            subscriptionId: 97199501078981314381821887969280644645474214415824181351277844695307424388955,
            callbackGasLimit: 500_000, // 500.000 gas
            // The address of ERC20 LINK Contract on Sepolia
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            account: 0xbD7f8Cb7963B11078fc8e06ca5043815Ed93b16A
        });
    }

    //    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
    //        NetworkConfig memory mainnetConfig = NetworkConfig({priceFeed: MAINNET_ETH_USD});
    //        return mainnetConfig;
    //    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMock =
            new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UINT_LINK);
        LinkToken linkToken = new LinkToken();
        uint256 subscriptionId = vrfCoordinatorMock.createSubscription();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether, //1e16
            interval: 30, // 30 seconds
            // https://docs.chain.link/vrf/v2-5/supported-networks#sepolia-testnet
            vrfCoordinator: address(vrfCoordinatorMock),
            // In local network this doesn't matter
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: subscriptionId,
            callbackGasLimit: 500_000, // 500.000 gas
            link: address(linkToken),
            account: DEFAULT_SENDER
        });

        return localNetworkConfig;
    }
}
