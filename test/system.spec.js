const { expect } = require("chai");
const { ethers } = require("hardhat");

const MESSAGE_PREFIX = ethers.keccak256(Buffer.from("AUTHORIZATION_V1"));

function buildDigest(chainId, vault, recipient, amount, authorizationId) {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return ethers.keccak256(
    abiCoder.encode(
      ["bytes32", "uint256", "address", "address", "uint256", "bytes32"],
      [MESSAGE_PREFIX, chainId, vault, recipient, amount, authorizationId]
    )
  );
}

async function signAuthorization(signer, chainId, vault, recipient, amount, authorizationId) {
  const digest = buildDigest(chainId, vault, recipient, amount, authorizationId);
  return signer.signMessage(ethers.getBytes(digest));
}

describe("SecureVault integration", function () {
  let deployer;
  let recipient;
  let other;
  let chainId;
  let manager;
  let vault;

  beforeEach(async function () {
    [deployer, recipient, other] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();
    chainId = Number(network.chainId);

    const AuthorizationManager = await ethers.getContractFactory("AuthorizationManager", deployer);
    manager = await AuthorizationManager.deploy(deployer.address);
    await manager.waitForDeployment();

    const SecureVault = await ethers.getContractFactory("SecureVault", deployer);
    vault = await SecureVault.deploy(manager.target);
    await vault.waitForDeployment();

    await manager.bindVault(vault.target);
  });

  it("accepts deposits and reports balance", async function () {
    const value = ethers.parseEther("1");
    await deployer.sendTransaction({ to: vault.target, value });
    expect(await vault.vaultBalance()).to.equal(value);
  });

  it("processes a valid withdrawal and consumes the authorization", async function () {
    const value = ethers.parseEther("1.5");
    await deployer.sendTransaction({ to: vault.target, value });

    const authId = ethers.keccak256(Buffer.from("auth-1"));
    const signature = await signAuthorization(
      deployer,
      chainId,
      vault.target,
      recipient.address,
      value,
      authId
    );

    const before = await ethers.provider.getBalance(recipient.address);
    const tx = await vault.connect(other).withdraw(recipient.address, value, authId, signature);
    await expect(tx).to.emit(vault, "Withdrawal").withArgs(recipient.address, value, authId);

    const after = await ethers.provider.getBalance(recipient.address);
    expect(after - before).to.equal(value);
    expect(await manager.consumed(authId)).to.equal(true);
  });

  it("rejects replayed authorizations", async function () {
    const value = ethers.parseEther("1");
    await deployer.sendTransaction({ to: vault.target, value });

    const authId = ethers.keccak256(Buffer.from("auth-replay"));
    const signature = await signAuthorization(
      deployer,
      chainId,
      vault.target,
      recipient.address,
      value,
      authId
    );

    await vault.withdraw(recipient.address, value, authId, signature);
    await expect(
      vault.withdraw(recipient.address, value, authId, signature)
    ).to.be.revertedWith("authorization used");
  });

  it("rejects invalid signatures", async function () {
    const value = ethers.parseEther("1");
    await deployer.sendTransaction({ to: vault.target, value });

    const authId = ethers.keccak256(Buffer.from("bad-sig"));
    const signature = await signAuthorization(
      other,
      chainId,
      vault.target,
      recipient.address,
      value,
      authId
    );

    await expect(
      vault.withdraw(recipient.address, value, authId, signature)
    ).to.be.revertedWith("bad signature");
  });
});
