// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HeirlockVault.sol";
import "./HeirlockVaultYield.sol";
import "./interfaces/IHeirlockVault.sol";

/**
 * @title HeirlockFactory
 * @notice Factory contract for deploying Heirlock vaults (basic and yield-enabled)
 * @dev Collects creation fees sent to treasury
 */
contract HeirlockFactory {
    
    // ============ Constants ============
    
    uint256 public constant BASIC_VAULT_FEE = 0.01 ether;
    uint256 public constant YIELD_VAULT_FEE = 0.02 ether;
    
    // ============ Immutable State ============
    
    address public immutable treasury;
    
    // Yield protocol addresses (for yield vaults)
    address public immutable lido;
    address public immutable wsteth;
    address public immutable aavePool;
    address public immutable curveStethPool;
    
    // ============ State ============
    
    address[] public allVaults;
    mapping(address => address[]) public vaultsByOwner;
    mapping(address => bool) public isYieldVault;
    
    // ============ Events ============
    
    event VaultCreated(
        address indexed owner, 
        address indexed vault, 
        uint256 inactivityThreshold,
        bool isYield,
        uint256 feePaid,
        uint256 timestamp
    );
    
    // ============ Errors ============
    
    error InsufficientFee(uint256 sent, uint256 required);
    error TreasuryTransferFailed();
    error InvalidAddress();
    
    // ============ Constructor ============
    
    /**
     * @notice Initialize factory with treasury and yield protocol addresses
     * @param _treasury Address that receives creation fees
     * @param _lido Lido stETH contract address
     * @param _wsteth Wrapped stETH contract address
     * @param _aavePool Aave V3 Pool address
     * @param _curveStethPool Curve stETH/ETH pool address
     */
    constructor(
        address _treasury,
        address _lido,
        address _wsteth,
        address _aavePool,
        address _curveStethPool
    ) {
        if (_treasury == address(0)) revert InvalidAddress();
        
        treasury = _treasury;
        lido = _lido;
        wsteth = _wsteth;
        aavePool = _aavePool;
        curveStethPool = _curveStethPool;
    }
    
    // ============ Vault Creation Functions ============
    
    /**
     * @notice Create a basic Heirlock vault (no yield features)
     * @dev Requires BASIC_VAULT_FEE (0.01 ETH)
     * @param _beneficiaries Array of beneficiary addresses and shares
     * @param _inactivityThreshold Seconds of inactivity before claimable
     * @return vault Address of the newly created vault
     */
    function createBasicVault(
        IHeirlockVault.Beneficiary[] calldata _beneficiaries,
        uint256 _inactivityThreshold
    ) external payable returns (address vault) {
        if (msg.value < BASIC_VAULT_FEE) {
            revert InsufficientFee(msg.value, BASIC_VAULT_FEE);
        }
        
        HeirlockVault newVault = new HeirlockVault(
            msg.sender,
            _beneficiaries,
            _inactivityThreshold
        );
        
        vault = address(newVault);
        
        _trackVault(vault, msg.sender, false);
        _collectFee(BASIC_VAULT_FEE);
        _refundExcess(BASIC_VAULT_FEE);
        
        emit VaultCreated(
            msg.sender, 
            vault, 
            _inactivityThreshold, 
            false,
            BASIC_VAULT_FEE,
            block.timestamp
        );
    }
    
    /**
     * @notice Create a yield-enabled Heirlock vault (Lido + Aave)
     * @dev Requires YIELD_VAULT_FEE (0.02 ETH)
     * @param _beneficiaries Array of beneficiary addresses and shares
     * @param _inactivityThreshold Seconds of inactivity before claimable
     * @return vault Address of the newly created vault
     */
    function createYieldVault(
        IHeirlockVault.Beneficiary[] calldata _beneficiaries,
        uint256 _inactivityThreshold
    ) external payable returns (address vault) {
        if (msg.value < YIELD_VAULT_FEE) {
            revert InsufficientFee(msg.value, YIELD_VAULT_FEE);
        }
        
        HeirlockVaultYield newVault = new HeirlockVaultYield(
            msg.sender,
            _beneficiaries,
            _inactivityThreshold,
            treasury,
            lido,
            wsteth,
            aavePool,
            curveStethPool
        );
        
        vault = address(newVault);
        
        _trackVault(vault, msg.sender, true);
        _collectFee(YIELD_VAULT_FEE);
        _refundExcess(YIELD_VAULT_FEE);
        
        emit VaultCreated(
            msg.sender, 
            vault, 
            _inactivityThreshold, 
            true,
            YIELD_VAULT_FEE,
            block.timestamp
        );
    }
    
    /**
     * @notice Legacy function - creates basic vault
     * @dev Kept for backwards compatibility
     */
    function createVault(
        IHeirlockVault.Beneficiary[] calldata _beneficiaries,
        uint256 _inactivityThreshold
    ) external payable returns (address vault) {
        return this.createBasicVault{value: msg.value}(_beneficiaries, _inactivityThreshold);
    }
    
    // ============ Internal Functions ============
    
    function _trackVault(address _vault, address _owner, bool _isYield) internal {
        allVaults.push(_vault);
        vaultsByOwner[_owner].push(_vault);
        isYieldVault[_vault] = _isYield;
    }
    
    function _collectFee(uint256 _fee) internal {
        (bool success, ) = treasury.call{value: _fee}("");
        if (!success) revert TreasuryTransferFailed();
    }
    
    function _refundExcess(uint256 _fee) internal {
        uint256 excess = msg.value - _fee;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            // Don't revert on refund failure
        }
    }
    
    // ============ View Functions ============
    
    function getBasicVaultFee() external pure returns (uint256) {
        return BASIC_VAULT_FEE;
    }
    
    function getYieldVaultFee() external pure returns (uint256) {
        return YIELD_VAULT_FEE;
    }
    
    function getVaultsByOwner(address _owner) external view returns (address[] memory) {
        return vaultsByOwner[_owner];
    }
    
    function getTotalVaults() external view returns (uint256) {
        return allVaults.length;
    }
    
    function getVaultAt(uint256 _index) external view returns (address) {
        require(_index < allVaults.length, "Index out of bounds");
        return allVaults[_index];
    }
    
    function getVaultCountByOwner(address _owner) external view returns (uint256) {
        return vaultsByOwner[_owner].length;
    }
    
    function getVaultInfo(address _vault) external view returns (
        bool exists,
        bool isYield,
        address vaultOwner
    ) {
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (allVaults[i] == _vault) {
                exists = true;
                isYield = isYieldVault[_vault];
                vaultOwner = IHeirlockVault(_vault).owner();
                return (exists, isYield, vaultOwner);
            }
        }
        return (false, false, address(0));
    }
    
    /**
     * @notice Get yield protocol addresses
     */
    function getYieldProtocols() external view returns (
        address _lido,
        address _wsteth,
        address _aavePool,
        address _curvePool
    ) {
        return (lido, wsteth, aavePool, curveStethPool);
    }
}
