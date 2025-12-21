import { ethers, network, run } from "hardhat";
import * as fs from "fs";
import * as path from "path";

// ============================================
// CONFIGURATION - SET YOUR TREASURY ADDRESS
// ============================================
const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS || "0xYOUR_TREASURY_ADDRESS_HERE";

async function main() {
  // Validate treasury address
  if (TREASURY_ADDRESS === "0xYOUR_TREASURY_ADDRESS_HERE" || !ethers.isAddress(TREASURY_ADDRESS)) {
    throw new Error(
      "Please set a valid TREASURY_ADDRESS in your .env file or replace the placeholder above"
    );
  }

  const [deployer] = await ethers.getSigners();
  
  console.log("=".repeat(60));
  console.log("HEIRLOCK DEPLOYMENT");
  console.log("=".repeat(60));
  console.log(`Network: ${network.name}`);
  console.log(`Chain ID: ${network.config.chainId}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Treasury: ${TREASURY_ADDRESS}`);
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);
  console.log("=".repeat(60));

  // Deploy Factory with treasury address
  console.log("\n[1/2] Deploying HeirlockFactory...");
  const Factory = await ethers.getContractFactory("HeirlockFactory");
  const factory = await Factory.deploy(TREASURY_ADDRESS);
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log(`    HeirlockFactory deployed to: ${factoryAddress}`);
  console.log(`    Treasury set to: ${TREASURY_ADDRESS}`);
  console.log(`    Creation fee: 0.01 ETH`);

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
  console.log(`  Treasury: ${TREASURY_ADDRESS}`);

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.config.chainId,
    deployer: deployer.address,
    treasury: TREASURY_ADDRESS,
    creationFee: "0.01 ETH",
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
        constructorArguments: [TREASURY_ADDRESS],
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
1. Verify treasury address ${TREASURY_ADDRESS} is correct
2. Update README.md with deployed addresses
3. Update frontend config with contract addresses
4. Test vault creation (costs 0.01 ETH)
5. Confirm fees arrive at treasury
  `);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
