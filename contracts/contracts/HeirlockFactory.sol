// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HeirlockVault.sol";
import "./interfaces/IHeirlockVault.sol";

/**
 * @title HeirlockFactory
 * @notice Factory contract for deploying individual Heirlock vaults
 * @dev Collects a fixed creation fee sent to treasury
 */
contract HeirlockFactory {
    
    // ============ Constants ============
    
    /// @notice Fee to create a vault (0.01 ETH)
    uint256 public constant CREATION_FEE = 0.01 ether;
    
    // ============ Immutable State ============
    
    /// @notice Treasury address that receives creation fees
    address public immutable treasury;
    
    // ============ State ============
    
    address[] public allVaults;
    mapping(address => address[]) public vaultsByOwner;
    
    // ============ Events ============
    
    event VaultCreated(
        address indexed owner, 
        address indexed vault, 
        uint256 inactivityThreshold,
        uint256 feePaid,
        uint256 timestamp
    );
    
    event FeesWithdrawn(address indexed to, uint256 amount);
    
    // ============ Errors ============
    
    error InsufficientFee(uint256 sent, uint256 required);
    error TreasuryTransferFailed();
    error InvalidTreasury();
    
    // ============ Constructor ============
    
    /**
     * @notice Initialize factory with treasury address
     * @param _treasury Address that will receive creation fees
     */
    constructor(address _treasury) {
        if (_treasury == address(0)) revert InvalidTreasury();
        treasury = _treasury;
    }
    
    // ============ Functions ============
    
    /**
     * @notice Create a new Heirlock vault
     * @dev Requires CREATION_FEE to be sent with transaction
     * @param _beneficiaries Array of beneficiary addresses and their share in basis points
     * @param _inactivityThreshold Seconds of inactivity before vault becomes claimable
     * @return vault Address of the newly created vault
     */
    function createVault(
        IHeirlockVault.Beneficiary[] calldata _beneficiaries,
        uint256 _inactivityThreshold
    ) external payable returns (address vault) {
        
        // Check fee
        if (msg.value < CREATION_FEE) {
            revert InsufficientFee(msg.value, CREATION_FEE);
        }
        
        // Deploy vault
        HeirlockVault newVault = new HeirlockVault(
            msg.sender,
            _beneficiaries,
            _inactivityThreshold
        );
        
        vault = address(newVault);
        
        // Track vault
        allVaults.push(vault);
        vaultsByOwner[msg.sender].push(vault);
        
        // Transfer fee to treasury
        (bool success, ) = treasury.call{value: CREATION_FEE}("");
        if (!success) revert TreasuryTransferFailed();
        
        // Refund excess ETH if any
        uint256 excess = msg.value - CREATION_FEE;
        if (excess > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: excess}("");
            // Don't revert on refund failure - vault is already created
            // User can recover via other means if needed
        }
        
        emit VaultCreated(
            msg.sender, 
            vault, 
            _inactivityThreshold, 
            CREATION_FEE,
            block.timestamp
        );
        
        return vault;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get the current creation fee
     * @return Fee amount in wei
     */
    function getCreationFee() external pure returns (uint256) {
        return CREATION_FEE;
    }
    
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
