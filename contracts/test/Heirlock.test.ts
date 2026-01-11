import { expect } from "chai";
import { ethers } from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { HeirlockFactory, HeirlockVault, HeirlockRegistry } from "../typechain-types";

describe("Heirlock", function () {
  // Time constants
  const ONE_MONTH = 30 * 24 * 60 * 60;
  const SIX_MONTHS = 6 * ONE_MONTH;
  const ONE_YEAR = 365 * 24 * 60 * 60;
  const TWO_YEARS = 2 * ONE_YEAR;

  // Fee constants
  const BASIC_VAULT_FEE = ethers.parseEther("0.01");
  const YIELD_VAULT_FEE = ethers.parseEther("0.02");

  // Basis points
  const BP_100 = 10000;
  const BP_50 = 5000;
  const BP_25 = 2500;

  async function deployFixture() {
    const [owner, treasury, beneficiary1, beneficiary2, beneficiary3, stranger] = 
      await ethers.getSigners();

    // Deploy Factory (with zero addresses for yield protocols in basic tests)
    const Factory = await ethers.getContractFactory("HeirlockFactory");
    const factory = await Factory.deploy(
      treasury.address,
      ethers.ZeroAddress, // lido
      ethers.ZeroAddress, // wsteth
      ethers.ZeroAddress, // aavePool
      ethers.ZeroAddress  // curvePool
    );

    // Deploy Registry
    const Registry = await ethers.getContractFactory("HeirlockRegistry");
    const registry = await Registry.deploy();

    // Deploy MockERC20 for token tests
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockERC20.deploy("Mock Token", "MOCK", 18);
    const mockUSDC = await MockERC20.deploy("Mock USDC", "USDC", 6);

    return { 
      factory, registry, mockToken, mockUSDC,
      owner, treasury, beneficiary1, beneficiary2, beneficiary3, stranger 
    };
  }

  describe("HeirlockFactory", function () {
    it("Should deploy with correct treasury", async function () {
      const { factory, treasury } = await loadFixture(deployFixture);
      expect(await factory.treasury()).to.equal(treasury.address);
    });

    it("Should return correct fee amounts", async function () {
      const { factory } = await loadFixture(deployFixture);
      expect(await factory.getBasicVaultFee()).to.equal(BASIC_VAULT_FEE);
      expect(await factory.getYieldVaultFee()).to.equal(YIELD_VAULT_FEE);
    });

    it("Should create basic vault with correct fee", async function () {
      const { factory, owner, treasury, beneficiary1 } = await loadFixture(deployFixture);
      
      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];
      const treasuryBalanceBefore = await ethers.provider.getBalance(treasury.address);
      
      const tx = await factory.createBasicVault(beneficiaries, SIX_MONTHS, { 
        value: BASIC_VAULT_FEE 
      });
      
      const receipt = await tx.wait();
      const treasuryBalanceAfter = await ethers.provider.getBalance(treasury.address);
      
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(BASIC_VAULT_FEE);
      expect(await factory.getTotalVaults()).to.equal(1);
    });

    it("Should reject vault creation with insufficient fee", async function () {
      const { factory, beneficiary1 } = await loadFixture(deployFixture);
      
      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];
      
      await expect(
        factory.createBasicVault(beneficiaries, SIX_MONTHS, { 
          value: ethers.parseEther("0.005") 
        })
      ).to.be.revertedWithCustomError(factory, "InsufficientFee");
    });

    it("Should refund excess ETH", async function () {
      const { factory, owner, beneficiary1 } = await loadFixture(deployFixture);
      
      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];
      const excessAmount = ethers.parseEther("0.05");
      
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      const tx = await factory.createBasicVault(beneficiaries, SIX_MONTHS, { 
        value: excessAmount 
      });
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      
      // Should only have spent BASIC_VAULT_FEE + gas
      const spent = balanceBefore - balanceAfter;
      expect(spent).to.be.closeTo(BASIC_VAULT_FEE + gasUsed, ethers.parseEther("0.001"));
    });

    it("Should track vaults by owner", async function () {
      const { factory, owner, beneficiary1 } = await loadFixture(deployFixture);
      
      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];
      
      await factory.createBasicVault(beneficiaries, SIX_MONTHS, { value: BASIC_VAULT_FEE });
      await factory.createBasicVault(beneficiaries, ONE_YEAR, { value: BASIC_VAULT_FEE });
      
      const ownerVaults = await factory.getVaultsByOwner(owner.address);
      expect(ownerVaults.length).to.equal(2);
    });
  });

  describe("HeirlockVault", function () {
    async function createVaultFixture() {
      const base = await loadFixture(deployFixture);
      const { factory, beneficiary1, beneficiary2 } = base;
      
      const beneficiaries = [
        { wallet: beneficiary1.address, basisPoints: BP_50 },
        { wallet: beneficiary2.address, basisPoints: BP_50 }
      ];
      
      const tx = await factory.createBasicVault(beneficiaries, SIX_MONTHS, { 
        value: BASIC_VAULT_FEE 
      });
      const receipt = await tx.wait();
      
      // Get vault address from event
      const event = receipt?.logs.find(
        (log: any) => log.fragment?.name === "VaultCreated"
      );
      const vaultAddress = (event as any).args.vault;
      
      const vault = await ethers.getContractAt("HeirlockVault", vaultAddress);
      
      return { ...base, vault, vaultAddress };
    }

    describe("Initialization", function () {
      it("Should set correct owner", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        expect(await vault.owner()).to.equal(owner.address);
      });

      it("Should set correct threshold", async function () {
        const { vault } = await loadFixture(createVaultFixture);
        expect(await vault.inactivityThreshold()).to.equal(SIX_MONTHS);
      });

      it("Should set correct beneficiaries", async function () {
        const { vault, beneficiary1, beneficiary2 } = await loadFixture(createVaultFixture);
        
        const beneficiaries = await vault.getBeneficiaries();
        expect(beneficiaries.length).to.equal(2);
        expect(beneficiaries[0].wallet).to.equal(beneficiary1.address);
        expect(beneficiaries[0].basisPoints).to.equal(BP_50);
      });

      it("Should set initial check-in time", async function () {
        const { vault } = await loadFixture(createVaultFixture);
        const lastCheckIn = await vault.lastCheckIn();
        expect(lastCheckIn).to.be.gt(0);
      });
    });

    describe("Deposits", function () {
      it("Should accept ETH deposits", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        
        const depositAmount = ethers.parseEther("1.0");
        await owner.sendTransaction({ to: await vault.getAddress(), value: depositAmount });
        
        expect(await ethers.provider.getBalance(await vault.getAddress())).to.equal(depositAmount);
      });

      it("Should emit ETHDeposited event", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        
        const depositAmount = ethers.parseEther("1.0");
        await expect(
          owner.sendTransaction({ to: await vault.getAddress(), value: depositAmount })
        ).to.emit(vault, "ETHDeposited").withArgs(owner.address, depositAmount);
      });
    });

    describe("Check-in", function () {
      it("Should update lastCheckIn timestamp", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        
        const initialCheckIn = await vault.lastCheckIn();
        await time.increase(ONE_MONTH);
        await vault.connect(owner).checkIn();
        
        expect(await vault.lastCheckIn()).to.be.gt(initialCheckIn);
      });

      it("Should only allow owner to check in", async function () {
        const { vault, stranger } = await loadFixture(createVaultFixture);
        
        await expect(vault.connect(stranger).checkIn()).to.be.revertedWith("Not owner");
      });

      it("Should emit CheckIn event", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        
        await expect(vault.connect(owner).checkIn()).to.emit(vault, "CheckIn");
      });
    });

    describe("Claimability", function () {
      it("Should not be claimable before threshold", async function () {
        const { vault } = await loadFixture(createVaultFixture);
        expect(await vault.isClaimable()).to.be.false;
      });

      it("Should be claimable after threshold", async function () {
        const { vault } = await loadFixture(createVaultFixture);
        
        await time.increase(SIX_MONTHS + 1);
        expect(await vault.isClaimable()).to.be.true;
      });

      it("Should report correct time until claimable", async function () {
        const { vault } = await loadFixture(createVaultFixture);
        
        const timeUntil = await vault.getTimeUntilClaimable();
        expect(timeUntil).to.be.closeTo(BigInt(SIX_MONTHS), BigInt(10));
      });

      it("Should return 0 time when already claimable", async function () {
        const { vault } = await loadFixture(createVaultFixture);
        
        await time.increase(SIX_MONTHS + 1);
        expect(await vault.getTimeUntilClaimable()).to.equal(0);
      });
    });

    describe("Distribution", function () {
      it("Should not allow distribution before threshold", async function () {
        const { vault, stranger } = await loadFixture(createVaultFixture);
        
        await expect(vault.connect(stranger).triggerDistribution())
          .to.be.revertedWith("Not yet claimable");
      });

      it("Should allow anyone to trigger distribution after threshold", async function () {
        const { vault, owner, stranger } = await loadFixture(createVaultFixture);
        
        // Fund vault
        await owner.sendTransaction({ 
          to: await vault.getAddress(), 
          value: ethers.parseEther("10.0") 
        });
        
        await time.increase(SIX_MONTHS + 1);
        
        await expect(vault.connect(stranger).triggerDistribution())
          .to.emit(vault, "DistributionTriggered");
      });

      it("Should calculate correct shares", async function () {
        const { vault, owner, beneficiary1, beneficiary2 } = await loadFixture(createVaultFixture);
        
        const depositAmount = ethers.parseEther("10.0");
        await owner.sendTransaction({ to: await vault.getAddress(), value: depositAmount });
        
        await time.increase(SIX_MONTHS + 1);
        await vault.triggerDistribution();
        
        // Each beneficiary should get 50%
        const [ethAmount1] = await vault.getClaimableAmounts(beneficiary1.address);
        const [ethAmount2] = await vault.getClaimableAmounts(beneficiary2.address);
        
        expect(ethAmount1).to.equal(ethers.parseEther("5.0"));
        expect(ethAmount2).to.equal(ethers.parseEther("5.0"));
      });
    });

    describe("Claims", function () {
      it("Should allow beneficiary to claim ETH", async function () {
        const { vault, owner, beneficiary1 } = await loadFixture(createVaultFixture);
        
        await owner.sendTransaction({ 
          to: await vault.getAddress(), 
          value: ethers.parseEther("10.0") 
        });
        
        await time.increase(SIX_MONTHS + 1);
        await vault.triggerDistribution();
        
        const balanceBefore = await ethers.provider.getBalance(beneficiary1.address);
        await vault.connect(beneficiary1).claimETH();
        const balanceAfter = await ethers.provider.getBalance(beneficiary1.address);
        
        // Should have received ~5 ETH (minus gas)
        expect(balanceAfter - balanceBefore).to.be.closeTo(
          ethers.parseEther("5.0"), 
          ethers.parseEther("0.01")
        );
      });

      it("Should prevent double claims", async function () {
        const { vault, owner, beneficiary1 } = await loadFixture(createVaultFixture);
        
        await owner.sendTransaction({ 
          to: await vault.getAddress(), 
          value: ethers.parseEther("10.0") 
        });
        
        await time.increase(SIX_MONTHS + 1);
        await vault.triggerDistribution();
        
        await vault.connect(beneficiary1).claimETH();
        
        await expect(vault.connect(beneficiary1).claimETH())
          .to.be.revertedWith("Nothing to claim");
      });
    });

    describe("Owner Withdrawals", function () {
      it("Should allow owner to withdraw ETH before distribution", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        
        await owner.sendTransaction({ 
          to: await vault.getAddress(), 
          value: ethers.parseEther("5.0") 
        });
        
        const balanceBefore = await ethers.provider.getBalance(owner.address);
        await vault.connect(owner).withdrawETH(ethers.parseEther("2.0"));
        const balanceAfter = await ethers.provider.getBalance(owner.address);
        
        expect(balanceAfter).to.be.gt(balanceBefore);
      });

      it("Should prevent withdrawals after distribution", async function () {
        const { vault, owner } = await loadFixture(createVaultFixture);
        
        await owner.sendTransaction({ 
          to: await vault.getAddress(), 
          value: ethers.parseEther("5.0") 
        });
        
        await time.increase(SIX_MONTHS + 1);
        await vault.triggerDistribution();
        
        await expect(vault.connect(owner).withdrawETH(ethers.parseEther("1.0")))
          .to.be.revertedWith("Already distributed");
      });
    });

    describe("Token Registration", function () {
      it("Should allow owner to register tokens", async function () {
        const { vault, owner, mockToken } = await loadFixture(createVaultFixture);
        
        await vault.connect(owner).registerToken(await mockToken.getAddress());
        
        const tokens = await vault.getRegisteredTokens();
        expect(tokens.length).to.equal(1);
        expect(tokens[0]).to.equal(await mockToken.getAddress());
      });

      it("Should prevent duplicate registration", async function () {
        const { vault, owner, mockToken } = await loadFixture(createVaultFixture);
        
        await vault.connect(owner).registerToken(await mockToken.getAddress());
        
        await expect(vault.connect(owner).registerToken(await mockToken.getAddress()))
          .to.be.revertedWith("Already registered");
      });
    });
  });

  describe("HeirlockRegistry", function () {
    async function createVaultWithRegistryFixture() {
      const base = await loadFixture(deployFixture);
      const { factory, registry, beneficiary1, beneficiary2 } = base;
      
      const beneficiaries = [
        { wallet: beneficiary1.address, basisPoints: BP_50 },
        { wallet: beneficiary2.address, basisPoints: BP_50 }
      ];
      
      const tx = await factory.createBasicVault(beneficiaries, SIX_MONTHS, { 
        value: BASIC_VAULT_FEE 
      });
      const receipt = await tx.wait();
      
      const event = receipt?.logs.find(
        (log: any) => log.fragment?.name === "VaultCreated"
      );
      const vaultAddress = (event as any).args.vault;
      const vault = await ethers.getContractAt("HeirlockVault", vaultAddress);
      
      return { ...base, vault, vaultAddress };
    }

    it("Should allow vault registration", async function () {
      const { registry, vault, owner } = await loadFixture(createVaultWithRegistryFixture);
      
      await registry.connect(owner).registerVault(await vault.getAddress());
      
      expect(await registry.isRegistered(await vault.getAddress())).to.be.true;
    });

    it("Should index beneficiaries", async function () {
      const { registry, vault, owner, beneficiary1 } = await loadFixture(createVaultWithRegistryFixture);
      
      await registry.connect(owner).registerVault(await vault.getAddress());
      
      const vaults = await registry.getVaultsForBeneficiary(beneficiary1.address);
      expect(vaults.length).to.equal(1);
      expect(vaults[0]).to.equal(await vault.getAddress());
    });

    it("Should track vault deadlines", async function () {
      const { registry, vault, owner } = await loadFixture(createVaultWithRegistryFixture);
      
      await registry.connect(owner).registerVault(await vault.getAddress());
      
      const details = await registry.getVaultDetails(await vault.getAddress());
      expect(details.deadline).to.be.gt(0);
      expect(details.isActive).to.be.true;
    });

    it("Should find vaults near deadline", async function () {
      const { registry, vault, owner } = await loadFixture(createVaultWithRegistryFixture);
      
      await registry.connect(owner).registerVault(await vault.getAddress());
      
      // Fast forward to near deadline
      await time.increase(SIX_MONTHS - ONE_MONTH);
      
      const [vaults, deadlines] = await registry.getVaultsNearDeadline(ONE_MONTH * 2);
      expect(vaults.length).to.equal(1);
    });
  });
});

// Note: MockERC20 is deployed from contracts/mocks/MockERC20.sol
