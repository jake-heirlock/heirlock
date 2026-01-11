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
    
    // ============ Core Functions ============
    
    /// @notice Check in to reset inactivity timer
    function checkIn() external;
    
    /// @notice Check if vault is claimable by beneficiaries
    function isClaimable() external view returns (bool);
    
    /// @notice Get seconds until vault becomes claimable
    function getTimeUntilClaimable() external view returns (uint256);
    
    /// @notice Get the check-in deadline timestamp
    function getCheckInDeadline() external view returns (uint256);
    
    /// @notice Get all beneficiaries
    function getBeneficiaries() external view returns (Beneficiary[] memory);
    
    /// @notice Get vault owner
    function owner() external view returns (address);
    
    /// @notice Get last check-in timestamp
    function lastCheckIn() external view returns (uint256);
    
    /// @notice Get inactivity threshold in seconds
    function inactivityThreshold() external view returns (uint256);
    
    /// @notice Check if distribution has been triggered
    function distributed() external view returns (bool);
}
