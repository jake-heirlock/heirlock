// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IHeirlockVault.sol";

/**
 * @title HeirlockVault
 * @notice Individual inheritance vault for a single owner
 * @dev Deployed via HeirlockFactory, one vault per user
 */
contract HeirlockVault is IHeirlockVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ Constants ============
    
    uint256 public constant MIN_THRESHOLD = 30 days;
    uint256 public constant MAX_THRESHOLD = 730 days;
    uint256 public constant BASIS_POINTS_TOTAL = 10000;
    uint256 public constant MAX_BENEFICIARIES = 10;
    uint256 public constant MAX_TOKENS = 50;
    
    // ============ State ============
    
    address public immutable owner;
    uint256 public lastCheckIn;
    uint256 public inactivityThreshold;
    bool public distributed;
    
    Beneficiary[] public beneficiaries;
    
    address[] public registeredTokens;
    mapping(address => bool) public isTokenRegistered;
    
    // beneficiary => token => amount (address(0) = ETH)
    mapping(address => mapping(address => uint256)) public claimableAmounts;
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier notDistributed() {
        require(!distributed, "Already distributed");
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _owner,
        Beneficiary[] memory _beneficiaries,
        uint256 _inactivityThreshold
    ) {
        require(_owner != address(0), "Invalid owner");
        require(_inactivityThreshold >= MIN_THRESHOLD, "Threshold too short");
        require(_inactivityThreshold <= MAX_THRESHOLD, "Threshold too long");
        
        owner = _owner;
        inactivityThreshold = _inactivityThreshold;
        lastCheckIn = block.timestamp;
        
        _setBeneficiaries(_beneficiaries);
    }
    
    // ============ Owner Functions ============
    
    /// @inheritdoc IHeirlockVault
    function checkIn() external onlyOwner notDistributed {
        lastCheckIn = block.timestamp;
        emit CheckIn(block.timestamp);
    }
    
    /// @notice Register a token for distribution
    function registerToken(address _token) external onlyOwner notDistributed {
        require(_token != address(0), "Invalid token");
        require(!isTokenRegistered[_token], "Already registered");
        require(registeredTokens.length < MAX_TOKENS, "Too many tokens");
        
        registeredTokens.push(_token);
        isTokenRegistered[_token] = true;
        
        emit TokenRegistered(_token);
    }
    
    /// @notice Register multiple tokens at once
    function registerTokens(address[] calldata _tokens) external onlyOwner notDistributed {
        require(registeredTokens.length + _tokens.length <= MAX_TOKENS, "Too many tokens");
        
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), "Invalid token");
            if (!isTokenRegistered[_tokens[i]]) {
                registeredTokens.push(_tokens[i]);
                isTokenRegistered[_tokens[i]] = true;
                emit TokenRegistered(_tokens[i]);
            }
        }
    }
    
    /// @notice Unregister a token from distribution
    function unregisterToken(address _token) external onlyOwner notDistributed {
        require(isTokenRegistered[_token], "Not registered");
        
        isTokenRegistered[_token] = false;
        
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            if (registeredTokens[i] == _token) {
                registeredTokens[i] = registeredTokens[registeredTokens.length - 1];
                registeredTokens.pop();
                break;
            }
        }
        
        emit TokenUnregistered(_token);
    }
    
    /// @notice Update beneficiaries and their share percentages
    function updateBeneficiaries(Beneficiary[] calldata _beneficiaries) 
        external 
        onlyOwner 
        notDistributed 
    {
        _setBeneficiaries(_beneficiaries);
        emit BeneficiariesUpdated(_beneficiaries);
    }
    
    /// @notice Update the inactivity threshold (resets check-in timer)
    function updateThreshold(uint256 _newThreshold) 
        external 
        onlyOwner 
        notDistributed 
    {
        require(_newThreshold >= MIN_THRESHOLD, "Threshold too short");
        require(_newThreshold <= MAX_THRESHOLD, "Threshold too long");
        
        inactivityThreshold = _newThreshold;
        lastCheckIn = block.timestamp;
        emit ThresholdUpdated(_newThreshold);
    }
    
    /// @notice Withdraw ETH from vault
    function withdrawETH(uint256 _amount) 
        external 
        onlyOwner 
        notDistributed 
        nonReentrant 
    {
        require(_amount <= address(this).balance, "Insufficient balance");
        
        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH transfer failed");
        
        emit ETHWithdrawn(owner, _amount);
    }
    
    /// @notice Withdraw tokens from vault
    function withdrawToken(address _token, uint256 _amount) 
        external 
        onlyOwner 
        notDistributed 
        nonReentrant 
    {
        IERC20(_token).safeTransfer(owner, _amount);
        emit TokenWithdrawn(_token, owner, _amount);
    }
    
    // ============ Distribution Functions ============
    
    /// @notice Trigger distribution after inactivity period
    function triggerDistribution() external notDistributed nonReentrant {
        require(isClaimable(), "Not yet claimable");
        
        distributed = true;
        
        uint256 ethBalance = address(this).balance;
        
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address wallet = beneficiaries[i].wallet;
            uint256 bp = beneficiaries[i].basisPoints;
            
            if (ethBalance > 0) {
                claimableAmounts[wallet][address(0)] = (ethBalance * bp) / BASIS_POINTS_TOTAL;
            }
            
            for (uint256 j = 0; j < registeredTokens.length; j++) {
                address token = registeredTokens[j];
                uint256 tokenBalance = IERC20(token).balanceOf(address(this));
                if (tokenBalance > 0) {
                    claimableAmounts[wallet][token] = (tokenBalance * bp) / BASIS_POINTS_TOTAL;
                }
            }
        }
        
        emit DistributionTriggered(msg.sender, block.timestamp);
    }
    
    /// @notice Claim ETH share
    function claimETH() external nonReentrant {
        require(distributed, "Distribution not triggered");
        
        uint256 ethAmount = claimableAmounts[msg.sender][address(0)];
        require(ethAmount > 0, "Nothing to claim");
        
        claimableAmounts[msg.sender][address(0)] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        
        emit ShareClaimed(msg.sender, address(0), ethAmount);
    }
    
    /// @notice Claim specific token shares
    function claimTokens(address[] calldata _tokens) external nonReentrant {
        require(distributed, "Distribution not triggered");
        
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 tokenAmount = claimableAmounts[msg.sender][_tokens[i]];
            if (tokenAmount > 0) {
                claimableAmounts[msg.sender][_tokens[i]] = 0;
                IERC20(_tokens[i]).safeTransfer(msg.sender, tokenAmount);
                emit ShareClaimed(msg.sender, _tokens[i], tokenAmount);
            }
        }
    }
    
    /// @notice Claim all shares (ETH + all registered tokens)
    function claimAll() external nonReentrant {
        require(distributed, "Distribution not triggered");
        
        uint256 ethAmount = claimableAmounts[msg.sender][address(0)];
        if (ethAmount > 0) {
            claimableAmounts[msg.sender][address(0)] = 0;
            (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            emit ShareClaimed(msg.sender, address(0), ethAmount);
        }
        
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            address token = registeredTokens[i];
            uint256 tokenAmount = claimableAmounts[msg.sender][token];
            if (tokenAmount > 0) {
                claimableAmounts[msg.sender][token] = 0;
                IERC20(token).safeTransfer(msg.sender, tokenAmount);
                emit ShareClaimed(msg.sender, token, tokenAmount);
            }
        }
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IHeirlockVault
    function isClaimable() public view returns (bool) {
        return block.timestamp > lastCheckIn + inactivityThreshold && !distributed;
    }
    
    /// @inheritdoc IHeirlockVault
    function getTimeUntilClaimable() external view returns (uint256) {
        uint256 claimableAt = lastCheckIn + inactivityThreshold;
        if (block.timestamp >= claimableAt) {
            return 0;
        }
        return claimableAt - block.timestamp;
    }
    
    /// @notice Get deadline timestamp for next check-in
    function getCheckInDeadline() external view returns (uint256) {
        return lastCheckIn + inactivityThreshold;
    }
    
    /// @notice Get all beneficiaries
    function getBeneficiaries() external view returns (Beneficiary[] memory) {
        return beneficiaries;
    }
    
    /// @notice Get number of beneficiaries
    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaries.length;
    }
    
    /// @notice Get all registered tokens
    function getRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }
    
    /// @notice Get number of registered tokens
    function getRegisteredTokenCount() external view returns (uint256) {
        return registeredTokens.length;
    }
    
    /// @notice Get vault status summary
    function getVaultStatus() external view returns (
        address vaultOwner,
        uint256 ethBalance,
        uint256 lastActivity,
        uint256 threshold,
        uint256 deadline,
        bool isActive,
        bool canClaim,
        uint256 beneficiaryCount,
        uint256 tokenCount
    ) {
        return (
            owner,
            address(this).balance,
            lastCheckIn,
            inactivityThreshold,
            lastCheckIn + inactivityThreshold,
            !distributed,
            isClaimable(),
            beneficiaries.length,
            registeredTokens.length
        );
    }
    
    /// @notice Get claimable amounts for a beneficiary
    function getClaimableAmounts(address _beneficiary) 
        external 
        view 
        returns (uint256 ethAmount, address[] memory tokens, uint256[] memory amounts) 
    {
        ethAmount = claimableAmounts[_beneficiary][address(0)];
        tokens = registeredTokens;
        amounts = new uint256[](registeredTokens.length);
        
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            amounts[i] = claimableAmounts[_beneficiary][registeredTokens[i]];
        }
    }
    
    // ============ Internal Functions ============
    
    function _setBeneficiaries(Beneficiary[] memory _beneficiaries) internal {
        require(_beneficiaries.length > 0, "Need at least one beneficiary");
        require(_beneficiaries.length <= MAX_BENEFICIARIES, "Too many beneficiaries");
        
        delete beneficiaries;
        
        uint256 totalBasisPoints = 0;
        
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            require(_beneficiaries[i].wallet != address(0), "Invalid beneficiary address");
            require(_beneficiaries[i].wallet != owner, "Owner cannot be beneficiary");
            require(_beneficiaries[i].basisPoints > 0, "Share must be > 0");
            
            totalBasisPoints += _beneficiaries[i].basisPoints;
            beneficiaries.push(_beneficiaries[i]);
        }
        
        require(totalBasisPoints == BASIS_POINTS_TOTAL, "Shares must total 100%");
    }
    
    // ============ Receive ETH ============
    
    receive() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }
    
    fallback() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }
}
