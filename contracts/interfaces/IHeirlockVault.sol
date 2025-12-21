// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IHeirlockVault
 * @notice Interface for Heirlock inheritance vaults
 */
interface IHeirlockVault {
    
    // ============ Structs ============
    
    struct Beneficiary {
        address wallet;
        uint256 basisPoints; // out of 10000 (e.g., 5000 = 50%)
    }
    
    // ============ Events ============
    
    event CheckIn(uint256 timestamp);
    event BeneficiariesUpdated(Beneficiary[] beneficiaries);
    event ThresholdUpdated(uint256 newThreshold);
    event ETHDeposited(address indexed from, uint256 amount);
    event TokenDeposited(address indexed token, address indexed from, uint256 amount);
    event TokenRegistered(address indexed token);
    event TokenUnregistered(address indexed token);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);
    event DistributionTriggered(address indexed triggeredBy, uint256 timestamp);
    event ShareClaimed(address indexed beneficiary, address indexed token, uint256 amount);
    
    // ============ Functions ============
    
    /// @notice Confirm owner is still active, resets inactivity timer
    function checkIn() external;
    
    /// @notice Check if vault can be claimed (owner inactive past threshold)
    /// @return True if claimable
    function isClaimable() external view returns (bool);
    
    /// @notice Get seconds until vault becomes claimable
    /// @return Seconds remaining, 0 if already claimable
    function getTimeUntilClaimable() external view returns (uint256);
}
