// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { MerkleDistributor, OwnedThreeStep, Pausable, EIP712 } from "src/MerkleDistributor.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";

contract MerkleDistributorUnitTest is Test {
    MerkleDistributor merkleDistributor;
    ERC20Mock paymentToken;

    address owner;
    address client;
    address contractor;

    bytes32 merkleRoot = 0xfb74e1a6f36e429e034de0ae290ff93edfa336d6e0d431cb241d4d98ceda2e6b; //script/data/output.json
    uint256 clientPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; //anvil account_0
    uint256 contractorPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; //anvil account_1
    uint256 amountToClaim = 25 ether;
    uint256 amountToSend = amountToClaim * 4;

    bytes32 proofOne = 0xf884e61898c71567fd4f44aa020453ed544cb775949e2087043630858aa9e609;
    bytes32 proofTwo = 0xf19a9e842b5a96e6e829203e375dfae8688610006eff2ecee5b1d5171631c970;
    bytes32[] proof = [proofOne, proofTwo];

    event Claimed(address indexed account, uint256 amount);
    event MerkleRootUpdated(bytes32 newMerkleRoot);
    event EndTimeUpdated(uint256 newEndTime);
    event Withdrawn(address indexed receiver, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = makeAddr("owner");
        client = vm.addr(clientPrivateKey);
        contractor = vm.addr(contractorPrivateKey);
        paymentToken = new ERC20Mock();
        merkleDistributor = new MerkleDistributor(owner, address(paymentToken), merkleRoot, 0);
        paymentToken.mint(address(merkleDistributor), amountToSend);
    }

    function test_setUpState() public view {
        assertTrue(address(merkleDistributor).code.length > 0);
        assertEq(merkleDistributor.owner(), owner);
        assertEq(merkleDistributor.endTime(), 0);
        assertEq(merkleDistributor.merkleRoot(), merkleRoot);
        assertEq(address(merkleDistributor.token()), address(paymentToken));
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);
    }

    function test_deploy_rewardsDistributor_reverts() public {
        vm.expectRevert(MerkleDistributor.ZeroAddressProvided.selector);
        new MerkleDistributor(address(0), address(paymentToken), merkleRoot, 0);
        vm.expectRevert(MerkleDistributor.ZeroAddressProvided.selector);
        new MerkleDistributor(owner, address(0), merkleRoot, 0);
        vm.expectRevert(MerkleDistributor.InvalidRoot.selector);
        new MerkleDistributor(owner, address(paymentToken), bytes32(0), 0);
    }

    function signMessage(uint256 privKey, address account) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashedMessage = merkleDistributor.getMessageHash(account, amountToClaim);
        (v, r, s) = vm.sign(privKey, hashedMessage);
    }

    function signMessageInvalid(uint256, address account) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashedMessage = merkleDistributor.getMessageHash(account, amountToClaim);
        (v, r, s) = vm.sign(contractorPrivateKey, hashedMessage);
    }

    function test_claim_by_referral() public {
        uint256 balanceBefore = paymentToken.balanceOf(client);
        assertFalse(merkleDistributor.isClaimed(client));

        vm.startPrank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(clientPrivateKey, client);
        vm.expectEmit(true, true, true, true);
        emit Claimed(client, amountToClaim);
        merkleDistributor.claim(client, amountToClaim, proof, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(client), balanceBefore + amountToClaim);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - amountToClaim);
        assertTrue(merkleDistributor.isClaimed(client));
    }

    function test_claim_by_another_referral_from_root() public {
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = bytes32(0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a);
        proof2[1] = bytes32(0xf19a9e842b5a96e6e829203e375dfae8688610006eff2ecee5b1d5171631c970);

        uint256 balanceBefore = paymentToken.balanceOf(contractor);
        assertFalse(merkleDistributor.isClaimed(contractor));

        vm.startPrank(contractor);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(contractorPrivateKey, contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, amountToClaim);
        merkleDistributor.claim(contractor, amountToClaim, proof2, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(contractor), balanceBefore + amountToClaim);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - amountToClaim);
        assertTrue(merkleDistributor.isClaimed(contractor));
    }

    function test_claim_by_gas_payer() public {
        uint256 balanceBefore = paymentToken.balanceOf(client);

        vm.prank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(clientPrivateKey, client);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Claimed(client, amountToClaim);
        merkleDistributor.claim(client, amountToClaim, proof, v, r, s);

        assertEq(paymentToken.balanceOf(client), balanceBefore + amountToClaim);
        assertEq(paymentToken.balanceOf(owner), 0);
    }

    function test_claim_reverts_AlreadyClaimed() public {
        test_claim_by_referral();
        assertEq(paymentToken.balanceOf(client), amountToClaim);
        assertTrue(merkleDistributor.isClaimed(client));

        vm.startPrank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(clientPrivateKey, client);
        vm.expectRevert(MerkleDistributor.AlreadyClaimed.selector);
        merkleDistributor.claim(client, amountToClaim, proof, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(client), amountToClaim);
        assertTrue(merkleDistributor.isClaimed(client));
    }

    function test_claim_reverts_InvalidSignature() public {
        uint256 balanceBefore = paymentToken.balanceOf(client);
        assertFalse(merkleDistributor.isClaimed(client));

        vm.startPrank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessageInvalid(clientPrivateKey, client);
        vm.expectRevert(MerkleDistributor.InvalidSignature.selector);
        merkleDistributor.claim(client, amountToClaim, proof, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(contractor), 0);
        assertEq(paymentToken.balanceOf(client), balanceBefore);
        assertFalse(merkleDistributor.isClaimed(client));

        vm.startPrank(client);
        (v, r, s) = signMessage(clientPrivateKey, client);
        vm.expectRevert(MerkleDistributor.InvalidSignature.selector);
        merkleDistributor.claim(client, amountToClaim + 1 wei, proof, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(client), balanceBefore);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);
        assertFalse(merkleDistributor.isClaimed(client));
    }

    function test_claim_reverts_InvalidProof() public {
        bytes32[] memory invalidProof = new bytes32[](2);
        invalidProof[0] = bytes32(0x9e9863c6fa5d32f9116da49891a1123e03ff838a2a71873fba03c27830e5d102);
        invalidProof[1] = bytes32(0x6faf2a16002ed3ddb5d372bffbe0f0f3f7141a9536e983cce95f3b40a4590346);

        uint256 balanceBefore = paymentToken.balanceOf(client);
        assertFalse(merkleDistributor.isClaimed(client));

        vm.startPrank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(clientPrivateKey, client);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        merkleDistributor.claim(client, amountToClaim, invalidProof, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(client), balanceBefore);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);
        assertFalse(merkleDistributor.isClaimed(client));
    }

    bytes32 newMerkleRoot = 0x71cc24e40153cd652202ed2d5f1da66f139637de876a4de32f1de1caa0dc8d34;

    function test_updateMerkleRoot() public {
        // bytes32 newMerkleRoot = 0x71cc24e40153cd652202ed2d5f1da66f139637de876a4de32f1de1caa0dc8d34;
        bytes32[] memory newProof = new bytes32[](2);
        newProof[0] = 0x9e9863c6fa5d32f9116da49891a1123e03ff838a2a71873fba03c27830e5d102;
        newProof[1] = 0xf884e61898c71567fd4f44aa020453ed544cb775949e2087043630858aa9e609;

        assertEq(merkleDistributor.merkleRoot(), merkleRoot);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        merkleDistributor.updateMerkleRoot(newMerkleRoot);
        vm.startPrank(owner);
        vm.expectRevert(MerkleDistributor.InvalidRoot.selector);
        merkleDistributor.updateMerkleRoot(bytes32(0));
        assertEq(merkleDistributor.merkleRoot(), merkleRoot);
        vm.expectEmit(true, false, false, true);
        emit MerkleRootUpdated(newMerkleRoot);
        merkleDistributor.updateMerkleRoot(newMerkleRoot);
        assertEq(merkleDistributor.merkleRoot(), newMerkleRoot);
        vm.stopPrank();
    }

    function test_claim_after_update_root() public {
        test_updateMerkleRoot();
        assertEq(merkleDistributor.merkleRoot(), newMerkleRoot);
        bytes32[] memory newProof = new bytes32[](1);
        newProof[0] = 0x9e9863c6fa5d32f9116da49891a1123e03ff838a2a71873fba03c27830e5d102;
        // newProof[1] = 0xf884e61898c71567fd4f44aa020453ed544cb775949e2087043630858aa9e609;

        uint256 balanceBefore = paymentToken.balanceOf(client);
        assertFalse(merkleDistributor.isClaimed(client));
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);

        vm.startPrank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(clientPrivateKey, client);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        merkleDistributor.claim(client, amountToClaim, newProof, v, r, s);
        vm.stopPrank();

        balanceBefore = paymentToken.balanceOf(client);
        assertFalse(merkleDistributor.isClaimed(client));
        assertEq(paymentToken.balanceOf(client), balanceBefore);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);

        balanceBefore = paymentToken.balanceOf(contractor);
        assertFalse(merkleDistributor.isClaimed(contractor));

        vm.startPrank(contractor);
        (v, r, s) = signMessage(contractorPrivateKey, contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, amountToClaim);
        merkleDistributor.claim(contractor, amountToClaim, newProof, v, r, s);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - amountToClaim);
        assertEq(paymentToken.balanceOf(contractor), balanceBefore + amountToClaim);
        assertTrue(merkleDistributor.isClaimed(contractor));
    }

    function test_claim_all_funds() public {
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);

        test_claim_by_referral();
        assertTrue(merkleDistributor.isClaimed(client));

        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - amountToClaim);

        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = bytes32(0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a);
        proof2[1] = bytes32(0xf19a9e842b5a96e6e829203e375dfae8688610006eff2ecee5b1d5171631c970);
        uint256 balanceBefore = paymentToken.balanceOf(contractor);
        assertFalse(merkleDistributor.isClaimed(contractor));
        vm.startPrank(contractor);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(contractorPrivateKey, contractor);
        merkleDistributor.claim(contractor, amountToClaim, proof2, v, r, s);
        vm.stopPrank();
        assertTrue(merkleDistributor.isClaimed(contractor));

        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - (amountToClaim * 2));

        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = bytes32(0xdcce9b6c41050fb750f018986e2fb5ef6a35bc4f62343dd6b5003e8abe473f74);
        proof3[1] = bytes32(0x6faf2a16002ed3ddb5d372bffbe0f0f3f7141a9536e983cce95f3b40a4590346);
        address claimer3 = vm.addr(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a);
        balanceBefore = paymentToken.balanceOf(claimer3);
        assertFalse(merkleDistributor.isClaimed(claimer3));
        vm.startPrank(claimer3);
        (v, r, s) = signMessage(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a, claimer3);
        merkleDistributor.claim(claimer3, amountToClaim, proof3, v, r, s);
        vm.stopPrank();
        assertTrue(merkleDistributor.isClaimed(claimer3));

        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - (amountToClaim * 3));

        bytes32[] memory proof4 = new bytes32[](2);
        proof4[0] = bytes32(0x9e9863c6fa5d32f9116da49891a1123e03ff838a2a71873fba03c27830e5d102);
        proof4[1] = bytes32(0x6faf2a16002ed3ddb5d372bffbe0f0f3f7141a9536e983cce95f3b40a4590346);
        address claimer4 = vm.addr(0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6);
        balanceBefore = paymentToken.balanceOf(claimer4);
        assertFalse(merkleDistributor.isClaimed(claimer4));
        vm.startPrank(claimer4);
        (v, r, s) = signMessage(0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6, claimer4);
        merkleDistributor.claim(claimer4, amountToClaim, proof4, v, r, s);
        vm.stopPrank();
        assertTrue(merkleDistributor.isClaimed(claimer4));

        assertEq(paymentToken.balanceOf(address(merkleDistributor)), 0);
    }

    function test_updateEndTime() public {
        assertEq(merkleDistributor.endTime(), 0);
        skip(1 days);
        uint256 pastEndTime = block.timestamp - 1;
        uint256 newEndTime = block.timestamp + 30 days;
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        merkleDistributor.updateEndTime(newEndTime);
        vm.startPrank(owner);
        vm.expectRevert(MerkleDistributor.EndTimeInPast.selector);
        merkleDistributor.updateEndTime(pastEndTime);
        assertEq(merkleDistributor.endTime(), 0);
        vm.expectEmit(true, false, false, true);
        emit EndTimeUpdated(newEndTime);
        merkleDistributor.updateEndTime(newEndTime);
        assertEq(merkleDistributor.endTime(), newEndTime);
        vm.stopPrank();
    }

    function test_claim_reverts_ClaimWindowFinished() public {
        uint256 newEndTime = block.timestamp + 30 days;
        vm.prank(owner);
        merkleDistributor.updateEndTime(newEndTime);
        assertEq(merkleDistributor.endTime(), newEndTime);
        skip(15 days);
        test_claim_by_referral();
        assertTrue(merkleDistributor.isClaimed(client));
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - amountToClaim);
        skip(31 days);
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = bytes32(0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a);
        proof2[1] = bytes32(0xf19a9e842b5a96e6e829203e375dfae8688610006eff2ecee5b1d5171631c970);
        assertFalse(merkleDistributor.isClaimed(contractor));
        vm.startPrank(contractor);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(contractorPrivateKey, contractor);
        vm.expectRevert(MerkleDistributor.ClaimWindowFinished.selector);
        merkleDistributor.claim(contractor, amountToClaim, proof2, v, r, s);
        vm.stopPrank();
        assertFalse(merkleDistributor.isClaimed(contractor));
        newEndTime = block.timestamp + 30 days;
        vm.prank(owner);
        merkleDistributor.updateEndTime(newEndTime);
        vm.prank(contractor);
        merkleDistributor.claim(contractor, amountToClaim, proof2, v, r, s);
        assertTrue(merkleDistributor.isClaimed(contractor));
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - (amountToClaim * 2));
    }

    function test_withdraw() public {
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend);
        assertEq(paymentToken.balanceOf(owner), 0);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        merkleDistributor.withdraw(notOwner);
        uint256 newEndTime = block.timestamp + 30 days;
        vm.startPrank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        merkleDistributor.withdraw(owner);
        merkleDistributor.pause();
        merkleDistributor.updateEndTime(newEndTime);
        vm.expectRevert(MerkleDistributor.NoWithdrawDuringClaim.selector);
        merkleDistributor.withdraw(owner);
        assertEq(paymentToken.balanceOf(owner), 0);
        skip(31 days);
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(owner, amountToSend);
        merkleDistributor.withdraw(owner);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), 0);
        assertEq(paymentToken.balanceOf(owner), amountToSend);
        vm.stopPrank();
    }

    function test_withdraw_after_claim() public {
        vm.prank(owner);
        merkleDistributor.updateEndTime(block.timestamp + 30 days);
        test_claim_by_referral();
        assertEq(paymentToken.balanceOf(client), amountToClaim);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), amountToSend - amountToClaim);
        assertEq(paymentToken.balanceOf(owner), 0);

        vm.startPrank(owner);
        merkleDistributor.pause();
        assertTrue(merkleDistributor.paused());
        vm.expectRevert(MerkleDistributor.NoWithdrawDuringClaim.selector);
        merkleDistributor.withdraw(owner);
        skip(31 days);
        merkleDistributor.withdraw(owner);
        assertEq(paymentToken.balanceOf(address(merkleDistributor)), 0);
        assertEq(paymentToken.balanceOf(owner), amountToSend - amountToClaim);
        vm.stopPrank();
    }

    function test_pause_unpause() public {
        assertFalse(merkleDistributor.paused());
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        merkleDistributor.pause();
        assertFalse(merkleDistributor.paused());

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit Paused(owner);
        merkleDistributor.pause();
        assertTrue(merkleDistributor.paused());
        vm.stopPrank();

        vm.prank(client);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(clientPrivateKey, client);
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        merkleDistributor.claim(client, amountToClaim, proof, v, r, s);

        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        merkleDistributor.unpause();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Unpaused(owner);
        merkleDistributor.unpause();
        assertFalse(merkleDistributor.paused());
        merkleDistributor.claim(client, amountToClaim, proof, v, r, s);
        assertTrue(merkleDistributor.isClaimed(client));
        vm.stopPrank();
    }
}
