# Import '.env' file
-include .env

# Install foundry modules
install:
	forge install foundry-rs/forge-std@v1.9.4 && \
	forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 && \
	forge install rari-capital/solmate@v6 && \
	forge install cyfrin/foundry-devops@0.2.3
# Remove foundry modules
remove:
	rm -rf lib

format:
	forge fmt

# Build the project
# ; is to write the command in the same line
build :; forge build
build-force :; forge build --force

test-simple:
	forge test
test-verbose:
	forge test -vvv
test-fork-sepolia:
	forge test --fork-url $(SEPOLIA_RPC_URL)
test-fork-sepolia-verbose:
	forge test --fork-url $(SEPOLIA_RPC_URL) -vvvv

coverage:
	forge coverage
coverage-debug:
	forge coverage --report debug > coverage-report.txt

anvil :; anvil

deploy-anvil:
	forge script script/DeployRaffle.s.sol:DeployRaffleScript \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
	--broadcast

# The @ is used to suppress the display of the command being executed
deploy-sepolia:
	@forge script script/DeployRaffle.s.sol:DeployRaffleScript \
    --rpc-url $(SEPOLIA_RPC_URL) \
    --account $(SEPOLIA_CAST_ACCOUNT) \
	--broadcast \
    --verify \
    --etherscan-api-key $(ETHERSCAN_API_KEY)