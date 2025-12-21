import { ethers, network, run } from "hardhat";
import * as fs from "fs";
import * as path from "path";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("=".repeat(60));
  console.log("HEIRLOCK DEPLOYMENT");
  console.log("=".repeat(60));
  console.log(`Network: ${network.name}`);
  console.log(`Chain ID: ${network.config.chainId}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);
  console.log("=".repeat(60));

  // Deploy Factory
  console.log("\n[1/2] Deploying HeirlockFactory...");
  const Factory = await ethers.getContractFactory("HeirlockFactory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log(`    HeirlockFactory deployed to: ${factoryAddress}`);

  // Deploy Registry
  console.log("\n[2/2] Deploying HeirlockRegistry...");
  const Registry = await ethers.getContractFactory("HeirlockRegistry");
  const registry = await Registry.deploy();
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress();
  console.log(`    HeirlockRegistry deployed to: ${registryAddress}`);

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYMENT COMPLETE");
  console.log("=".repeat(60));
  console.log(`\nContract Addresses:`);
  console.log(`  Factory:  ${factoryAddress}`);
  console.log(`  Registry: ${registryAddress}`);

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.config.chainId,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      factory: factoryAddress,
      registry: registryAddress,
    },
  };

  // Save to deployments folder
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const deploymentPath = path.join(deploymentsDir, `${network.name}.json`);
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment saved to: ${deploymentPath}`);

  // Verify on Etherscan (if not localhost)
  if (network.name !== "localhost" && network.name !== "hardhat") {
    console.log("\nWaiting for block confirmations before verification...");
    
    await factory.deploymentTransaction()?.wait(5);
    await registry.deploymentTransaction()?.wait(5);

    console.log("\nVerifying contracts on Etherscan...");
    
    try {
      await run("verify:verify", {
        address: factoryAddress,
        constructorArguments: [],
      });
      console.log("  Factory verified");
    } catch (e: any) {
      if (e.message.includes("Already Verified")) {
        console.log("  Factory already verified");
      } else {
        console.log(`  Factory verification failed: ${e.message}`);
      }
    }

    try {
      await run("verify:verify", {
        address: registryAddress,
        constructorArguments: [],
      });
      console.log("  Registry verified");
    } catch (e: any) {
      if (e.message.includes("Already Verified")) {
        console.log("  Registry already verified");
      } else {
        console.log(`  Registry verification failed: ${e.message}`);
      }
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log("NEXT STEPS");
  console.log("=".repeat(60));
  console.log(`
1. Update README.md with deployed addresses
2. Update frontend config with contract addresses
3. Test vault creation on ${network.name}
  `);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
