// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AuthorizationManager} from "./AuthorizationManager.sol";

/// @title SecureVault
/// @notice Holds funds and permits withdrawals only after verified authorization.
contract SecureVault is ReentrancyGuard {
    event Deposited(address indexed sender, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount, bytes32 authorizationId);

    AuthorizationManager public immutable authorizationManager;
    mapping(address => uint256) public withdrawnByRecipient;
    uint256 public totalWithdrawn;

    constructor(AuthorizationManager manager) {
        address managerAddress = address(manager);
        require(managerAddress != address(0), "invalid manager");
        authorizationManager = manager;
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Executes an authorized withdrawal.
    /// @dev Relies entirely on AuthorizationManager for permission validation.
    function withdraw(
        address payable recipient,
        uint256 amount,
        bytes32 authorizationId,
        bytes calldata signature
    ) external nonReentrant {
        require(recipient != address(0), "invalid recipient");
        require(amount > 0, "zero amount");

        bool approved = authorizationManager.verifyAuthorization(
            address(this),
            block.chainid,
            recipient,
            amount,
            authorizationId,
            signature
        );
        require(approved, "authorization failed");
        require(address(this).balance >= amount, "insufficient vault balance");

        totalWithdrawn += amount;
        withdrawnByRecipient[recipient] += amount;

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "transfer failed");

        emit Withdrawal(recipient, amount, authorizationId);
    }

    /// @notice Convenience helper for observers.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
