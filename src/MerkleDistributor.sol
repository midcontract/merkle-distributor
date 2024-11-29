// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { MerkleProofLib } from "@solbase/utils/MerkleProofLib.sol";
import { OwnedThreeStep } from "@solbase/auth/OwnedThreeStep.sol";
import { ReentrancyGuard } from "@solbase/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Pausable } from "@openzeppelin/utils/Pausable.sol";

/// @title Merkle Distributor
/// @notice A contract for distributing rewards based on Merkle proofs and EIP-712 signatures.
contract MerkleDistributor is OwnedThreeStep, Pausable, ReentrancyGuard, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                       CONFIGURATION & STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The EIP-712 typehash for earnings claim messages.
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("RewardsClaim(address account,uint256 amount)");

    /// @notice The ERC20 token used for rewards.
    IERC20 public token;

    /// @notice The Merkle root of the rewards distribution.
    bytes32 public merkleRoot;

    /// @notice The distribution end time, after which claims are no longer accepted.
    uint256 public endTime;

    /// @notice Tracks if an account has already claimed its rewards.
    /// @dev Prevents multiple claims from the same address by marking it as claimed after the first claim.
    mapping(address user => bool claimed) public isClaimed;

    /// @notice Represents a claim request for referral rewards.
    /// @dev Used in the EIP-712 signature validation.
    /// @param account The address of the account claiming rewards.
    /// @param amount The amount of rewards to claim.
    struct RewardsClaim {
        address account;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS & EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Thrown when a user attempts to claim an already-claimed reward.
    error AlreadyClaimed();
    /// @dev Thrown when a claim signature is invalid.
    error InvalidSignature();
    /// @dev Thrown when a provided Merkle proof is invalid.
    error InvalidProof();
    /// @dev Thrown when a zero Merkle root is provided.
    error InvalidRoot();
    /// @dev Thrown when zero address usage where prohibited.
    error ZeroAddressProvided();
    /// @dev Thrown when a claim is attempted after the designated claim window has closed.
    error ClaimWindowFinished();
    /// @dev Thrown when attempting to set an end time that is in the past.
    error EndTimeInPast();
    /// @dev Thrown when a withdrawal attempt is made before the claiming period has ended.
    error NoWithdrawDuringClaim();

    /// @notice Emitted when an account claims referral earnings.
    /// @param account The address of the account claiming earnings.
    /// @param amount The amount of earnings claimed.
    event Claimed(address indexed account, uint256 amount);

    /// @notice Emitted when the Merkle root is updated.
    /// @param newMerkleRoot The new Merkle root hash for reward distribution.
    event MerkleRootUpdated(bytes32 newMerkleRoot);

    /// @notice Emitted when the claiming end time is updated.
    /// @param newEndTime The new end time for the rewards claiming period.
    event EndTimeUpdated(uint256 newEndTime);

    /// @notice Emitted when the owner withdraws the remaining balance from the contract.
    /// @param receiver The address receiving the withdrawn balance.
    /// @param amount The amount of tokens withdrawn.
    event Withdrawn(address indexed receiver, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _owner Address of the contract owner.
    /// @param _rewardsToken Address of the ERC20 token for distribution.
    /// @param _merkleRoot Initial Merkle root for distribution, must be non-zero.
    /// @param _endTime End time for claiming rewards (may be zero to indicate no end time).
    constructor(address _owner, address _rewardsToken, bytes32 _merkleRoot, uint256 _endTime)
        OwnedThreeStep(_owner)
        EIP712("Merkle Rewards Distributor", "1.0.0")
    {
        if (_owner == address(0) || _rewardsToken == address(0)) revert ZeroAddressProvided();
        if (_merkleRoot == bytes32(0)) revert InvalidRoot();

        token = IERC20(_rewardsToken);
        merkleRoot = _merkleRoot;
        endTime = _endTime;
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims referral earnings for the caller.
    /// @dev Verifies the Merkle proof and signature before transferring earnings.
    /// @param _account The address of the account claiming earnings.
    /// @param _amount The amount of earnings to claim.
    /// @param _merkleProof Array of hashes in the Merkle proof.
    /// @param _v Part of the ECDSA signature.
    /// @param _r Part of the ECDSA signature.
    /// @param _s Part of the ECDSA signature.
    function claim(address _account, uint256 _amount, bytes32[] calldata _merkleProof, uint8 _v, bytes32 _r, bytes32 _s)
        external
        whenNotPaused
        nonReentrant
    {
        if (endTime != 0 && block.timestamp > endTime) revert ClaimWindowFinished();
        if (isClaimed[_account]) revert AlreadyClaimed();

        // Verify signature.
        if (!_isValidSignature(_account, getMessageHash(_account, _amount), _v, _r, _s)) {
            revert InvalidSignature();
        }

        // Verify the Merkle proof.
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_account, _amount))));
        if (!MerkleProofLib.verify(_merkleProof, merkleRoot, leaf)) {
            revert InvalidProof();
        }

        // Mark it claimed and send the token.
        isClaimed[_account] = true;
        token.safeTransfer(_account, _amount);

        emit Claimed(_account, _amount);
    }

    /// @notice Returns the hash of the message for the EIP-712 signature.
    /// @param _account The address of the account.
    /// @param _amount The amount of earnings.
    /// @return The EIP-712 message hash.
    function getMessageHash(address _account, uint256 _amount) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(MESSAGE_TYPEHASH, RewardsClaim({ account: _account, amount: _amount })))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the Merkle root, only callable by the contract owner.
    /// @param _merkleRoot New Merkle root for the reward distribution, must be non-zero.
    function updateMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        if (_merkleRoot == bytes32(0)) revert InvalidRoot();
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    /// @notice Updates the end time for claiming rewards, only callable by the contract owner.
    /// @dev Sets a new end time, which must be either zero (no end) or a future timestamp.
    /// @param _endTime The new end time for claiming rewards.
    function updateEndTime(uint256 _endTime) external onlyOwner {
        if (_endTime != 0 && _endTime < block.timestamp) revert EndTimeInPast();
        endTime = _endTime;
        emit EndTimeUpdated(_endTime);
    }

    /// @notice Withdraws the entire token balance from the contract, only callable by the owner.
    /// @dev Ensures the withdrawal is only allowed after the claiming period has ended.
    /// @param _receiver The address to which the withdrawn balance will be sent.
    function withdraw(address _receiver) external onlyOwner whenPaused {
        if (block.timestamp < endTime) revert NoWithdrawDuringClaim();
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(_receiver, balance);
        emit Withdrawn(_receiver, balance);
    }

    /// @notice Pauses the contract, preventing new claims and certain owner functions.
    /// @dev Once paused, the contract’s state must be unpaused for any functions restricted by `whenNotPaused` to be
    /// called.
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing claims and restricted functions to resume.
    /// @dev It re-enables all contract functionality that was restricted by `whenNotPaused`.
    function unpause() public onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Checks if a signature is valid by comparing the recovered address to the expected signer.
    /// @return True if the signature is valid and matches `_signer`.
    function _isValidSignature(address _signer, bytes32 _digest, uint8 _v, bytes32 _r, bytes32 _s)
        internal
        pure
        returns (bool)
    {
        (address actualSigner,,) = ECDSA.tryRecover(_digest, _v, _r, _s);
        return (actualSigner == _signer);
    }
}
