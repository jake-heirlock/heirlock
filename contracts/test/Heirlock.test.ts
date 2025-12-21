import { expect } from "chai";
import { ethers } from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { HeirlockFactory, HeirlockVault, HeirlockRegistry, MockERC20 } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("Heirlock", function () {
  // Time constants
  const ONE_MONTH = 30 * 24 * 60 * 60;
  const SIX_MONTHS = 6 * ONE_MONTH;
  const ONE_YEAR = 365 * 24 * 60 * 60;
  const TWO_YEARS = 2 * ONE_YEAR;

  // Basis points
  const BP_100 = 10000;
  const BP_50 = 5000;
  const BP_25 = 2500;

  async function deployFixture() {
    const [owner, beneficiary1, beneficiary2, beneficiary3, stranger] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("HeirlockFactory");
    const factory = await Factory.deploy();

    const Registry = await ethers.getContractFactory("HeirlockRegistry");
    const registry = await Registry.deploy();

    const MockToken = await ethers.getContractFactory("MockERC20");
    const tokenA = await MockToken.deploy("Token A", "TKNA", ethers.parseEther("1000000"));
    const tokenB = await MockToken.deploy("Token B", "TKNB", ethers.parseEther("1000000"));

    return { factory, registry, tokenA, tokenB, owner, beneficiary1, beneficiary2, beneficiary3, stranger };
  }

  async function createVaultFixture() {
    const base = await loadFixture(deployFixture);
    const { factory, owner, beneficiary1, beneficiary2 } = base;

    const beneficiaries = [
      { wallet: beneficiary1.address, basisPoints: BP_50 },
      { wallet: beneficiary2.address, basisPoints: BP_50 }
    ];

    const tx = await factory.createVault(beneficiaries, SIX_MONTHS);
    const receipt = await tx.wait();
    
    const event = receipt?.logs.find(
      (log: any) => log.fragment?.name === "VaultCreated"
    );
    const vaultAddress = (event as any).args.vault;

    const vault = await ethers.getContractAt("HeirlockVault", vaultAddress);

    return { ...base, vault, vaultAddress };
  }

  async function fundedVaultFixture() {
    const base = await loadFixture(createVaultFixture);
    const { vault, tokenA, tokenB, owner } = base;

    await owner.sendTransaction({
      to: await vault.getAddress(),
      value: ethers.parseEther("10")
    });

    await tokenA.transfer(await vault.getAddress(), ethers.parseEther("1000"));
    await tokenB.transfer(await vault.getAddress(), ethers.parseEther("500"));

    await vault.registerTokens([await tokenA.getAddress(), await tokenB.getAddress()]);

    return base;
  }

  // ============================================
  // FACTORY TESTS
  // ============================================

  describe("HeirlockFactory", function () {
    it("should create a vault with correct parameters", async function () {
      const { factory, owner, beneficiary1 } = await loadFixture(deployFixture);

      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];

      await expect(factory.createVault(beneficiaries, SIX_MONTHS))
        .to.emit(factory, "VaultCreated");

      expect(await factory.getTotalVaults()).to.equal(1);
      expect(await factory.getVaultCountByOwner(owner.address)).to.equal(1);
    });

    it("should allow multiple vaults per owner", async function () {
      const { factory, owner, beneficiary1, beneficiary2 } = await loadFixture(deployFixture);

      const ben1 = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];
      const ben2 = [{ wallet: beneficiary2.address, basisPoints: BP_100 }];

      await factory.createVault(ben1, ONE_MONTH);
      await factory.createVault(ben2, ONE_YEAR);

      expect(await factory.getVaultCountByOwner(owner.address)).to.equal(2);
    });

    it("should reject invalid threshold (too short)", async function () {
      const { factory, beneficiary1 } = await loadFixture(deployFixture);
      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];

      await expect(factory.createVault(beneficiaries, ONE_MONTH - 1))
        .to.be.revertedWith("Threshold too short");
    });

    it("should reject invalid threshold (too long)", async function () {
      const { factory, beneficiary1 } = await loadFixture(deployFixture);
      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];

      await expect(factory.createVault(beneficiaries, TWO_YEARS + 1))
        .to.be.revertedWith("Threshold too long");
    });

    it("should reject beneficiaries that don't total 100%", async function () {
      const { factory, beneficiary1, beneficiary2 } = await loadFixture(deployFixture);
      const beneficiaries = [
        { wallet: beneficiary1.address, basisPoints: BP_50 },
        { wallet: beneficiary2.address, basisPoints: BP_25 }
      ];

      await expect(factory.createVault(beneficiaries, SIX_MONTHS))
        .to.be.revertedWith("Shares must total 100%");
    });
  });

  // ============================================
  // VAULT BASIC TESTS
  // ============================================

  describe("HeirlockVault - Basic", function () {
    it("should have correct initial state", async function () {
      const { vault, owner } = await loadFixture(createVaultFixture);

      expect(await vault.owner()).to.equal(owner.address);
      expect(await vault.inactivityThreshold()).to.equal(SIX_MONTHS);
      expect(await vault.distributed()).to.equal(false);
      expect(await vault.getBeneficiaryCount()).to.equal(2);
    });

    it("should accept ETH deposits", async function () {
      const { vault, owner } = await loadFixture(createVaultFixture);
      const depositAmount = ethers.parseEther("5");

      await expect(owner.sendTransaction({
        to: await vault.getAddress(),
        value: depositAmount
      })).to.emit(vault, "ETHDeposited").withArgs(owner.address, depositAmount);

      expect(await ethers.provider.getBalance(await vault.getAddress())).to.equal(depositAmount);
    });

    it("should accept token deposits", async function () {
      const { vault, tokenA } = await loadFixture(createVaultFixture);
      const depositAmount = ethers.parseEther("100");

      await tokenA.transfer(await vault.getAddress(), depositAmount);
      expect(await tokenA.balanceOf(await vault.getAddress())).to.equal(depositAmount);
    });
  });

  // ============================================
  // CHECK-IN TESTS
  // ============================================

  describe("HeirlockVault - Check-in", function () {
    it("should allow owner to check in", async function () {
      const { vault } = await loadFixture(createVaultFixture);

      await time.increase(ONE_MONTH);
      
      await expect(vault.checkIn()).to.emit(vault, "CheckIn");
    });

    it("should reject check-in from non-owner", async function () {
      const { vault, stranger } = await loadFixture(createVaultFixture);

      await expect(vault.connect(stranger).checkIn())
        .to.be.revertedWith("Not owner");
    });

    it("should reset claimable timer on check-in", async function () {
      const { vault } = await loadFixture(createVaultFixture);

      await time.increase(SIX_MONTHS - 1000);
      expect(await vault.isClaimable()).to.equal(false);

      await vault.checkIn();

      await time.increase(1000);
      expect(await vault.isClaimable()).to.equal(false);
    });

    it("should return correct time until claimable", async function () {
      const { vault } = await loadFixture(createVaultFixture);

      const timeUntil = await vault.getTimeUntilClaimable();
      expect(timeUntil).to.be.closeTo(BigInt(SIX_MONTHS), BigInt(10));

      await time.increase(ONE_MONTH);
      
      const timeUntil2 = await vault.getTimeUntilClaimable();
      expect(timeUntil2).to.be.closeTo(BigInt(SIX_MONTHS - ONE_MONTH), BigInt(10));
    });
  });

  // ============================================
  // TOKEN REGISTRATION TESTS
  // ============================================

  describe("HeirlockVault - Token Registration", function () {
    it("should allow owner to register tokens", async function () {
      const { vault, tokenA } = await loadFixture(createVaultFixture);

      await expect(vault.registerToken(await tokenA.getAddress()))
        .to.emit(vault, "TokenRegistered")
        .withArgs(await tokenA.getAddress());

      expect(await vault.getRegisteredTokenCount()).to.equal(1);
      expect(await vault.isTokenRegistered(await tokenA.getAddress())).to.equal(true);
    });

    it("should allow batch token registration", async function () {
      const { vault, tokenA, tokenB } = await loadFixture(createVaultFixture);

      await vault.registerTokens([await tokenA.getAddress(), await tokenB.getAddress()]);

      expect(await vault.getRegisteredTokenCount()).to.equal(2);
    });

    it("should allow owner to unregister tokens", async function () {
      const { vault, tokenA, tokenB } = await loadFixture(createVaultFixture);

      await vault.registerTokens([await tokenA.getAddress(), await tokenB.getAddress()]);
      await vault.unregisterToken(await tokenA.getAddress());

      expect(await vault.getRegisteredTokenCount()).to.equal(1);
      expect(await vault.isTokenRegistered(await tokenA.getAddress())).to.equal(false);
    });

    it("should reject registration from non-owner", async function () {
      const { vault, tokenA, stranger } = await loadFixture(createVaultFixture);

      await expect(vault.connect(stranger).registerToken(await tokenA.getAddress()))
        .to.be.revertedWith("Not owner");
    });
  });

  // ============================================
  // OWNER WITHDRAWAL TESTS
  // ============================================

  describe("HeirlockVault - Owner Withdrawals", function () {
    it("should allow owner to withdraw ETH", async function () {
      const { vault, owner } = await loadFixture(fundedVaultFixture);
      const withdrawAmount = ethers.parseEther("5");
      
      await expect(vault.withdrawETH(withdrawAmount))
        .to.emit(vault, "ETHWithdrawn")
        .withArgs(owner.address, withdrawAmount);

      expect(await ethers.provider.getBalance(await vault.getAddress()))
        .to.equal(ethers.parseEther("5"));
    });

    it("should allow owner to withdraw tokens", async function () {
      const { vault, tokenA, owner } = await loadFixture(fundedVaultFixture);
      const withdrawAmount = ethers.parseEther("500");

      await expect(vault.withdrawToken(await tokenA.getAddress(), withdrawAmount))
        .to.emit(vault, "TokenWithdrawn");

      expect(await tokenA.balanceOf(await vault.getAddress()))
        .to.equal(ethers.parseEther("500"));
    });

    it("should reject withdrawals from non-owner", async function () {
      const { vault, stranger } = await loadFixture(fundedVaultFixture);

      await expect(vault.connect(stranger).withdrawETH(ethers.parseEther("1")))
        .to.be.revertedWith("Not owner");
    });
  });

  // ============================================
  // DISTRIBUTION TESTS
  // ============================================

  describe("HeirlockVault - Distribution", function () {
    it("should not allow distribution before threshold", async function () {
      const { vault, beneficiary1 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS - 100);

      await expect(vault.connect(beneficiary1).triggerDistribution())
        .to.be.revertedWith("Not yet claimable");
    });

    it("should allow distribution after threshold", async function () {
      const { vault, beneficiary1 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);

      await expect(vault.connect(beneficiary1).triggerDistribution())
        .to.emit(vault, "DistributionTriggered");

      expect(await vault.distributed()).to.equal(true);
    });

    it("should calculate correct shares for beneficiaries", async function () {
      const { vault, beneficiary1, beneficiary2 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      const [ethAmount1] = await vault.getClaimableAmounts(beneficiary1.address);
      const [ethAmount2] = await vault.getClaimableAmounts(beneficiary2.address);

      expect(ethAmount1).to.equal(ethers.parseEther("5"));
      expect(ethAmount2).to.equal(ethers.parseEther("5"));
    });

    it("should not allow double distribution", async function () {
      const { vault, beneficiary1 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      await expect(vault.connect(beneficiary1).triggerDistribution())
        .to.be.revertedWith("Already distributed");
    });

    it("should prevent owner actions after distribution", async function () {
      const { vault, beneficiary1 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      await expect(vault.checkIn())
        .to.be.revertedWith("Already distributed");
      
      await expect(vault.withdrawETH(ethers.parseEther("1")))
        .to.be.revertedWith("Already distributed");
    });
  });

  // ============================================
  // CLAIM TESTS
  // ============================================

  describe("HeirlockVault - Claims", function () {
    it("should allow beneficiary to claim ETH", async function () {
      const { vault, beneficiary1 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      const balanceBefore = await ethers.provider.getBalance(beneficiary1.address);
      
      await expect(vault.connect(beneficiary1).claimETH())
        .to.emit(vault, "ShareClaimed")
        .withArgs(beneficiary1.address, ethers.ZeroAddress, ethers.parseEther("5"));

      const balanceAfter = await ethers.provider.getBalance(beneficiary1.address);
      expect(balanceAfter - balanceBefore).to.be.closeTo(
        ethers.parseEther("5"),
        ethers.parseEther("0.01")
      );
    });

    it("should allow beneficiary to claim tokens", async function () {
      const { vault, beneficiary1, tokenA, tokenB } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      await vault.connect(beneficiary1).claimTokens([
        await tokenA.getAddress(),
        await tokenB.getAddress()
      ]);

      expect(await tokenA.balanceOf(beneficiary1.address)).to.equal(ethers.parseEther("500"));
      expect(await tokenB.balanceOf(beneficiary1.address)).to.equal(ethers.parseEther("250"));
    });

    it("should allow beneficiary to claim all at once", async function () {
      const { vault, beneficiary1, tokenA, tokenB } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      await vault.connect(beneficiary1).claimAll();

      expect(await tokenA.balanceOf(beneficiary1.address)).to.equal(ethers.parseEther("500"));
      expect(await tokenB.balanceOf(beneficiary1.address)).to.equal(ethers.parseEther("250"));
    });

    it("should not allow double claims", async function () {
      const { vault, beneficiary1 } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      await vault.connect(beneficiary1).claimETH();

      await expect(vault.connect(beneficiary1).claimETH())
        .to.be.revertedWith("Nothing to claim");
    });

    it("should not allow non-beneficiary to claim", async function () {
      const { vault, stranger } = await loadFixture(fundedVaultFixture);

      await time.increase(SIX_MONTHS + 1);
      await vault.triggerDistribution();

      await expect(vault.connect(stranger).claimETH())
        .to.be.revertedWith("Nothing to claim");
    });
  });

  // ============================================
  // CONFIGURATION UPDATE TESTS
  // ============================================

  describe("HeirlockVault - Configuration Updates", function () {
    it("should allow updating beneficiaries", async function () {
      const { vault, beneficiary1, beneficiary3 } = await loadFixture(createVaultFixture);

      const newBeneficiaries = [
        { wallet: beneficiary1.address, basisPoints: BP_25 },
        { wallet: beneficiary3.address, basisPoints: BP_25 + BP_50 }
      ];

      await expect(vault.updateBeneficiaries(newBeneficiaries))
        .to.emit(vault, "BeneficiariesUpdated");

      const bens = await vault.getBeneficiaries();
      expect(bens[1].wallet).to.equal(beneficiary3.address);
    });

    it("should allow updating threshold and reset timer", async function () {
      const { vault } = await loadFixture(createVaultFixture);

      await time.increase(ONE_MONTH * 3);

      await vault.updateThreshold(ONE_YEAR);

      expect(await vault.inactivityThreshold()).to.equal(ONE_YEAR);
      
      const timeUntil = await vault.getTimeUntilClaimable();
      expect(timeUntil).to.be.closeTo(BigInt(ONE_YEAR), BigInt(10));
    });
  });

  // ============================================
  // REGISTRY TESTS
  // ============================================

  describe("HeirlockRegistry", function () {
    it("should allow vault registration", async function () {
      const { vault, registry, owner } = await loadFixture(createVaultFixture);

      await expect(registry.registerVault(await vault.getAddress()))
        .to.emit(registry, "VaultRegistered")
        .withArgs(await vault.getAddress(), owner.address);
    });

    it("should index vaults by beneficiary", async function () {
      const { vault, registry, beneficiary1 } = await loadFixture(createVaultFixture);

      await registry.registerVault(await vault.getAddress());

      const vaults = await registry.getVaultsAsBeneficiary(beneficiary1.address);
      expect(vaults.length).to.equal(1);
      expect(vaults[0]).to.equal(await vault.getAddress());
    });

    it("should find vaults near deadline", async function () {
      const { vault, registry } = await loadFixture(createVaultFixture);

      await registry.registerVault(await vault.getAddress());

      await time.increase(SIX_MONTHS - 1000);

      const nearDeadline = await registry.getVaultsNearDeadline(2000);
      expect(nearDeadline.length).to.equal(1);
    });
  });

  // ============================================
  // EDGE CASE TESTS
  // ============================================

  describe("Edge Cases", function () {
    it("should handle single beneficiary with 100%", async function () {
      const { factory, owner, beneficiary1, tokenA } = await loadFixture(deployFixture);

      const beneficiaries = [{ wallet: beneficiary1.address, basisPoints: BP_100 }];
      const tx = await factory.createVault(beneficiaries, ONE_MONTH);
      const receipt = await tx.wait();
      const event = receipt?.logs.find((log: any) => log.fragment?.name === "VaultCreated");
      const vaultAddress = (event as any).args.vault;
      const vault = await ethers.getContractAt("HeirlockVault", vaultAddress);

      await owner.sendTransaction({ to: vaultAddress, value: ethers.parseEther("10") });
      await tokenA.transfer(vaultAddress, ethers.parseEther("100"));
      await vault.registerToken(await tokenA.getAddress());

      await time.increase(ONE_MONTH + 1);
      await vault.connect(beneficiary1).triggerDistribution();
      await vault.connect(beneficiary1).claimAll();

      expect(await tokenA.balanceOf(beneficiary1.address)).to.equal(ethers.parseEther("100"));
    });

    it("should handle uneven percentage splits", async function () {
      const { factory, owner, beneficiary1, beneficiary2, beneficiary3 } = await loadFixture(deployFixture);

      const beneficiaries = [
        { wallet: beneficiary1.address, basisPoints: 3333 },
        { wallet: beneficiary2.address, basisPoints: 3333 },
        { wallet: beneficiary3.address, basisPoints: 3334 }
      ];

      const tx = await factory.createVault(beneficiaries, ONE_MONTH);
      const receipt = await tx.wait();
      const event = receipt?.logs.find((log: any) => log.fragment?.name === "VaultCreated");
      const vaultAddress = (event as any).args.vault;
      const vault = await ethers.getContractAt("HeirlockVault", vaultAddress);

      await owner.sendTransaction({ to: vaultAddress, value: ethers.parseEther("10") });

      await time.increase(ONE_MONTH + 1);
      await vault.triggerDistribution();

      const [amt1] = await vault.getClaimableAmounts(beneficiary1.address);
      const [amt2] = await vault.getClaimableAmounts(beneficiary2.address);
      const [amt3] = await vault.getClaimableAmounts(beneficiary3.address);

      expect(amt1 + amt2 + amt3).to.be.closeTo(ethers.parseEther("10"), ethers.parseEther("0.001"));
    });

    it("should handle empty token balance during distribution", async function () {
      const { vault, beneficiary1, tokenA } = await loadFixture(createVaultFixture);

      await vault.registerToken(await tokenA.getAddress());

      await time.increase(SIX_MONTHS + 1);
      
      await vault.triggerDistribution();

      const [, , amounts] = await vault.getClaimableAmounts(beneficiary1.address);
      expect(amounts[0]).to.equal(0);
    });
  });
});
