// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HeirlockVault.sol";
import "./interfaces/IHeirlockVault.sol";

/**
 * @title HeirlockFactory
 * @notice Factory contract for deploying individual Heirlock vaults
 * @dev No admin functions, no special permissions
 */
contract HeirlockFactory {
    
    // ============ Events ============
    
    event VaultCreated(
        address indexed owner, 
        address indexed vault, 
        uint256 inactivityThreshold,
        uint256 timestamp
    );
    
    // ============ State ============
    
    address[] public allVaults;
    mapping(address => address[]) public vaultsByOwner;
    
    // ============ Functions ============
    
    /**
     * @notice Create a new Heirlock vault
     * @param _beneficiaries Array of beneficiary addresses and their share in basis points
     * @param _inactivityThreshold Seconds of inactivity before vault becomes claimable
     * @return vault Address of the newly created vault
     */
    function createVault(
        IHeirlockVault.Beneficiary[] calldata _beneficiaries,
        uint256 _inactivityThreshold
    ) external returns (address vault) {
        
        HeirlockVault newVault = new HeirlockVault(
            msg.sender,
            _beneficiaries,
            _inactivityThreshold
        );
        
        vault = address(newVault);
        
        allVaults.push(vault);
        vaultsByOwner[msg.sender].push(vault);
        
        emit VaultCreated(msg.sender, vault, _inactivityThreshold, block.timestamp);
        
        return vault;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get all vaults owned by an address
     * @param _owner Owner address to query
     * @return Array of vault addresses
     */
    function getVaultsByOwner(address _owner) external view returns (address[] memory) {
        return vaultsByOwner[_owner];
    }
    
    /**
     * @notice Get total number of vaults created
     * @return Total vault count
     */
    function getTotalVaults() external view returns (uint256) {
        return allVaults.length;
    }
    
    /**
     * @notice Get vault address by index
     * @param _index Index in allVaults array
     * @return Vault address
     */
    function getVaultAt(uint256 _index) external view returns (address) {
        require(_index < allVaults.length, "Index out of bounds");
        return allVaults[_index];
    }
    
    /**
     * @notice Get number of vaults owned by an address
     * @param _owner Owner address to query
     * @return Number of vaults
     */
    function getVaultCountByOwner(address _owner) external view returns (uint256) {
        return vaultsByOwner[_owner].length;
    }
}
