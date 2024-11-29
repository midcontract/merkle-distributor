// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { MerkleDistributor } from "src/MerkleDistributor.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";

contract DeployMerkleDistributorScript is Script {
    MerkleDistributor merkleDistributor;
    address rewardsToken;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;
    uint256 endTime;
    bytes32 merkleRoot = 0xfb74e1a6f36e429e034de0ae290ff93edfa336d6e0d431cb241d4d98ceda2e6b;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        rewardsToken = PolAmoyConfig.MOCK_USDT;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        merkleDistributor = new MerkleDistributor(ownerPublicKey, address(rewardsToken), merkleRoot, endTime);
        console.log("==factory addr=%s", address(merkleDistributor));
        assert(address(merkleDistributor) != address(0));
        vm.stopBroadcast();
    }
}
