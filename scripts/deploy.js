const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const provider = deployer.provider;
  const { chainId } = await provider.getNetwork();

  console.log(`Deploying with ${deployer.address}`);
  console.log(`Network: ${network.name} (chainId ${chainId})`);

  const AuthorizationManager = await ethers.getContractFactory("AuthorizationManager");
  const manager = await AuthorizationManager.deploy(deployer.address);
  await manager.waitForDeployment();
  console.log(`AuthorizationManager deployed at ${manager.target}`);

  const SecureVault = await ethers.getContractFactory("SecureVault");
  const vault = await SecureVault.deploy(manager.target);
  await vault.waitForDeployment();
  console.log(`SecureVault deployed at ${vault.target}`);

  const bindTx = await manager.bindVault(vault.target);
  await bindTx.wait();
  console.log("AuthorizationManager bound to vault");

  const output = {
    network: {
      name: network.name,
      chainId: Number(chainId),
    },
    authorizedSigner: deployer.address,
    authorizationManager: manager.target,
    vault: vault.target,
    timestamp: new Date().toISOString(),
  };

  const outPath = path.join(__dirname, "..", "deployment-output.json");
  fs.writeFileSync(outPath, JSON.stringify(output, null, 2));
  console.log(`Deployment info written to ${outPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
