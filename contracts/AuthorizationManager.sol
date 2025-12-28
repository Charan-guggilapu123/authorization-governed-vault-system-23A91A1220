// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title AuthorizationManager
/// @notice Validates off-chain generated withdrawal permissions and tracks replay protection.
contract AuthorizationManager is Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    event AuthorizationConsumed(
        bytes32 indexed authorizationId,
        address indexed vault,
        address indexed recipient,
        uint256 amount
    );
    event VaultBound(address indexed vault);

    address public immutable authorizedSigner;
    address public vault;
    mapping(bytes32 => bool) public consumed;

    constructor(address signer) Ownable(msg.sender) {
        require(signer != address(0), "invalid signer");
        authorizedSigner = signer;
    }

    /// @notice One-time binding to the vault instance that will call this manager.
    function bindVault(address vaultAddress) external onlyOwner {
        require(vaultAddress != address(0), "invalid vault");
        require(vault == address(0), "vault already bound");
        vault = vaultAddress;
        emit VaultBound(vaultAddress);
    }

    /// @notice Confirms and consumes an authorization for a withdrawal.
    /// @dev Reverts on invalid or replayed authorizations. Only callable by the bound vault.
    function verifyAuthorization(
        address vaultAddress,
        uint256 chainId,
        address recipient,
        uint256 amount,
        bytes32 authorizationId,
        bytes calldata signature
    ) external returns (bool) {
        require(vault != address(0), "vault uninitialized");
        require(msg.sender == vault, "unauthorized caller");
        require(vaultAddress == vault, "vault mismatch");
        require(chainId == block.chainid, "chain mismatch");
        require(!consumed[authorizationId], "authorization used");

        bytes32 digest = _computeDigest(vaultAddress, chainId, recipient, amount, authorizationId)
            .toEthSignedMessageHash();
        address recovered = ECDSA.recover(digest, signature);
        require(recovered == authorizedSigner, "bad signature");

        consumed[authorizationId] = true;
        emit AuthorizationConsumed(authorizationId, vaultAddress, recipient, amount);
        return true;
    }

    /// @notice Returns the hash to be signed off-chain for a withdrawal authorization.
    function computeMessageHash(
        address vaultAddress,
        uint256 chainId,
        address recipient,
        uint256 amount,
        bytes32 authorizationId
    ) external pure returns (bytes32) {
        return _computeDigest(vaultAddress, chainId, recipient, amount, authorizationId);
    }

    function _computeDigest(
        address vaultAddress,
        uint256 chainId,
        address recipient,
        uint256 amount,
        bytes32 authorizationId
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("AUTHORIZATION_V1"),
                chainId,
                vaultAddress,
                recipient,
                amount,
                authorizationId
            )
        );
    }
}
