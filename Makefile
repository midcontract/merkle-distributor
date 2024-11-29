# include .env file and export its env vars
# (-include to ignore error if it does not exist)
include .env

.PHONY: update build size inspect selectors test trace gas test-contract test-contract-gas trace-contract test-test trace-test clean snapshot anvil deploy

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Build & test
# deps
update :; forge update
build :; forge build
size :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty
# get the list of function selectors
selectors :; forge inspect ${contract} methods --pretty

# local tests without fork
test :; forge test --match-contract UnitTest -vvv
trace :; forge test --match-contract UnitTest -vvvv
gas :; forge test --match-contract UnitTest --gas-report
test-contract :; forge test -vvv --match-contract $(contract)
test-contract-gas :; forge test --gas-report --match-contract ${contract}
trace-contract :; forge test -vvvv --match-contract $(contract)
test-test :; forge test -vvv --match-test $(test)
trace-test :; forge test -vvvv --match-test $(test)

clean :; forge clean
snapshot :; forge snapshot
coverage :; forge coverage

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

DEPLOY_URL := ${POLYGON_AMOY_RPC} #${SEPOLIA_ALCHEMY_RPC_URL}
SCAN_API_KEY := ${POLYGONSCAN_API_KEY} #${ETHERSCAN_API_KEY}

# Generate Merkle Input file
generate-input :; forge script script/01_GenerateInput.s.sol:GenerateInput
# Generating Merkle Proof
generate-proof :; forge script script/02_MakeMerkle.s.sol:MakeMerkle
# Deploy Merkle Distributor
deploy-merkle-distributor :; source .env && forge script script/03_DeployMerkleDistributor.s.sol:DeployMerkleDistributorScript --rpc-url ${DEPLOY_URL} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${SCAN_API_KEY} -vvvv
