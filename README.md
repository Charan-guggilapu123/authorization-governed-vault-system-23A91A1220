## Authorization-Governed Vault System

This repository implements a two-contract vault architecture where withdrawals are only executed after an explicit on-chain authorization flow. The vault never verifies signatures directly and relies on a dedicated authorization manager to validate and consume off-chain permissions.

### Structure
- contracts/AuthorizationManager.sol – validates signatures, enforces replay protection, binds to one vault
- contracts/SecureVault.sol – holds funds, emits deposits, pulls authorization checks before paying out
- scripts/deploy.js – deploys manager → vault, binds them, and writes deployment-output.json
- tests/system.spec.js – integration tests for deposits, valid withdrawal, replay rejection, bad signature rejection
- docker/Dockerfile and docker/entrypoint.sh – container build and deployment runner
- docker-compose.yml – spins up an Anvil node and deploys contracts on start

### Authorization design
- Message hash (unsigned): `keccak256(abi.encode(keccak256("AUTHORIZATION_V1"), chainId, vault, recipient, amount, authorizationId))`
- The signer (set at AuthorizationManager construction) signs the **EIP-191** prefixed message (`toEthSignedMessageHash`).
- Parameters bind each authorization to: chain, vault instance, recipient, amount, and a unique authorizationId (nonce-like). Replay protection is enforced by `consumed[authorizationId]` in AuthorizationManager.

### Usage
1) Install dependencies and run tests locally:
	- npm install
	- npx hardhat test

2) Manual local run without Docker (uses default Hardhat local network):
	- npx hardhat node (separate terminal)
	- RPC_URL=http://127.0.0.1:8545 PRIVATE_KEY=<dev-key> npx hardhat run scripts/deploy.js --network local

3) Dockerized flow (recommended for evaluators):
	- docker-compose up --build
	- Wait for logs to show deployed addresses; deployment-output.json will be written in the container workdir (and visible in logs).

### Generating an authorization off-chain
Pseudo-steps using ethers v6 (Node):
```js
const prefix = ethers.keccak256(Buffer.from("AUTHORIZATION_V1"));
const digest = ethers.keccak256(
  ethers.AbiCoder.defaultAbiCoder().encode(
	 ["bytes32", "uint256", "address", "address", "uint256", "bytes32"],
	 [prefix, chainId, vaultAddress, recipient, amountWei, authorizationId]
  )
);
const signature = await signer.signMessage(ethers.getBytes(digest));
```
Present `(recipient, amountWei, authorizationId, signature)` to `SecureVault.withdraw`.

### Security notes
- AuthorizationManager checks: caller must be the bound vault, chainId must match `block.chainid`, signature must come from the configured signer, and `authorizationId` must be unused.
- SecureVault performs state updates before transferring value and is guarded by `ReentrancyGuard`.
- Initialization is single-use: AuthorizationManager’s `bindVault` can only be called once.

### Observability
- Deposits emit `Deposited(address sender, uint256 amount)` from the vault’s receive handler.
- Successful withdrawals emit `Withdrawal(address recipient, uint256 amount, bytes32 authorizationId)`.
- Authorization consumption emits `AuthorizationConsumed(bytes32 authorizationId, address vault, address recipient, uint256 amount)`.

### Known assumptions
- A single signer address governs authorizations; rotate by redeploying if necessary.
- The system targets a single bound vault instance per AuthorizationManager to avoid cross-contract replay surface.