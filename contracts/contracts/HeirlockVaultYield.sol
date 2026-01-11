// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IHeirlockVault.sol";
import "./interfaces/IYieldInterfaces.sol";

/**
 * @title HeirlockVaultYield
 * @notice Inheritance vault with optional yield generation via Lido (ETH) and Aave (stablecoins)
 * @dev Deployed via HeirlockFactory with 0.02 ETH fee
 */
contract HeirlockVaultYield is IHeirlockVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ Constants ============
    
    uint256 public constant MIN_THRESHOLD = 30 days;
    uint256 public constant MAX_THRESHOLD = 730 days;
    uint256 public constant BASIS_POINTS_TOTAL = 10000;
    uint256 public constant MAX_BENEFICIARIES = 10;
    uint256 public constant MAX_TOKENS = 50;
    uint256 public constant YIELD_FEE_BP = 1000; // 10% fee on yield
    
    // ============ Mainnet Addresses ============
    // These should be updated per network or passed via constructor
    
    address public immutable LIDO;           // stETH
    address public immutable WSTETH;         // Wrapped stETH
    address public immutable AAVE_POOL;      // Aave V3 Pool
    address public immutable CURVE_STETH_POOL; // Curve stETH/ETH
    address public immutable treasury;       // Protocol treasury for yield fees
    
    // ============ State ============
    
    address public immutable owner;
    uint256 public lastCheckIn;
    uint256 public inactivityThreshold;
    bool public distributed;
    
    Beneficiary[] public beneficiaries;
    
    // Token tracking
    address[] public registeredTokens;
    mapping(address => bool) public isTokenRegistered;
    
    // Yield tracking
    uint256 public ethPrincipal;      // Original ETH deposited (not staked)
    uint256 public stakedETHPrincipal; // ETH principal that was staked
    mapping(address => uint256) public tokenPrincipal;  // Original token amounts
    mapping(address => uint256) public lentTokenPrincipal; // Token principal that was lent
    mapping(address => address) public tokenToAToken;   // token => aToken mapping
    
    // Claimable amounts after distribution
    mapping(address => mapping(address => uint256)) public claimableAmounts;
    
    // ============ Events ============
    
    event ETHStaked(uint256 amount, uint256 stETHReceived);
    event ETHUnstaked(uint256 stETHAmount, uint256 ethReceived);
    event TokenLent(address indexed token, uint256 amount);
    event TokenWithdrawnFromAave(address indexed token, uint256 amount);
    event YieldFeeCollected(address indexed token, uint256 amount);
    
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
        uint256 _inactivityThreshold,
        address _treasury,
        address _lido,
        address _wsteth,
        address _aavePool,
        address _curvePool
    ) {
        require(_owner != address(0), "Invalid owner");
        require(_treasury != address(0), "Invalid treasury");
        require(_inactivityThreshold >= MIN_THRESHOLD, "Threshold too short");
        require(_inactivityThreshold <= MAX_THRESHOLD, "Threshold too long");
        
        owner = _owner;
        treasury = _treasury;
        inactivityThreshold = _inactivityThreshold;
        lastCheckIn = block.timestamp;
        
        LIDO = _lido;
        WSTETH = _wsteth;
        AAVE_POOL = _aavePool;
        CURVE_STETH_POOL = _curvePool;
        
        _setBeneficiaries(_beneficiaries);
    }
    
    // ============ Owner Functions ============
    
    function checkIn() external onlyOwner notDistributed {
        lastCheckIn = block.timestamp;
        emit CheckIn(block.timestamp);
    }
    
    function registerToken(address _token) external onlyOwner notDistributed {
        require(_token != address(0), "Invalid token");
        require(!isTokenRegistered[_token], "Already registered");
        require(registeredTokens.length < MAX_TOKENS, "Too many tokens");
        
        registeredTokens.push(_token);
        isTokenRegistered[_token] = true;
        emit TokenRegistered(_token);
    }
    
    function registerTokens(address[] calldata _tokens) external onlyOwner notDistributed {
        require(registeredTokens.length + _tokens.length <= MAX_TOKENS, "Too many tokens");
        
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!isTokenRegistered[_tokens[i]] && _tokens[i] != address(0)) {
                registeredTokens.push(_tokens[i]);
                isTokenRegistered[_tokens[i]] = true;
                emit TokenRegistered(_tokens[i]);
            }
        }
    }
    
    function unregisterToken(address _token) external onlyOwner notDistributed {
        require(isTokenRegistered[_token], "Not registered");
        require(lentTokenPrincipal[_token] == 0, "Withdraw from Aave first");
        
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
    
    function updateBeneficiaries(Beneficiary[] calldata _beneficiaries) 
        external onlyOwner notDistributed 
    {
        _setBeneficiaries(_beneficiaries);
        emit BeneficiariesUpdated(_beneficiaries);
    }
    
    function updateThreshold(uint256 _newThreshold) external onlyOwner notDistributed {
        require(_newThreshold >= MIN_THRESHOLD, "Threshold too short");
        require(_newThreshold <= MAX_THRESHOLD, "Threshold too long");
        
        inactivityThreshold = _newThreshold;
        lastCheckIn = block.timestamp;
        emit ThresholdUpdated(_newThreshold);
    }
    
    // ============ Deposit Functions ============
    
    function depositETH() external payable onlyOwner notDistributed {
        require(msg.value > 0, "No ETH sent");
        ethPrincipal += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }
    
    function depositToken(address _token, uint256 _amount) external onlyOwner notDistributed {
        require(_amount > 0, "Zero amount");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        tokenPrincipal[_token] += _amount;
        
        if (!isTokenRegistered[_token]) {
            require(registeredTokens.length < MAX_TOKENS, "Too many tokens");
            registeredTokens.push(_token);
            isTokenRegistered[_token] = true;
            emit TokenRegistered(_token);
        }
        emit TokenDeposited(_token, msg.sender, _amount);
    }
    
    // ============ Yield Functions - ETH Staking (Lido) ============
    
    /// @notice Stake ETH to Lido, receive stETH
    function stakeETH(uint256 _amount) external onlyOwner notDistributed nonReentrant {
        require(_amount > 0, "Zero amount");
        require(_amount <= address(this).balance, "Insufficient ETH");
        require(LIDO != address(0), "Lido not configured");
        
        // Track principal being staked
        uint256 fromPrincipal = _amount > ethPrincipal ? ethPrincipal : _amount;
        ethPrincipal -= fromPrincipal;
        stakedETHPrincipal += fromPrincipal;
        
        // Stake to Lido
        uint256 stETHBefore = ILido(LIDO).balanceOf(address(this));
        ILido(LIDO).submit{value: _amount}(address(0));
        uint256 stETHReceived = ILido(LIDO).balanceOf(address(this)) - stETHBefore;
        
        emit ETHStaked(_amount, stETHReceived);
    }
    
    /// @notice Unstake stETH via Curve (instant, may have slippage)
    /// @param _stETHAmount Amount of stETH to unstake
    /// @param _minETHOut Minimum ETH to receive (slippage protection)
    function unstakeETH(uint256 _stETHAmount, uint256 _minETHOut) 
        external onlyOwner notDistributed nonReentrant 
    {
        require(_stETHAmount > 0, "Zero amount");
        require(CURVE_STETH_POOL != address(0), "Curve not configured");
        
        uint256 stETHBalance = ILido(LIDO).balanceOf(address(this));
        require(_stETHAmount <= stETHBalance, "Insufficient stETH");
        
        // Approve Curve pool
        ILido(LIDO).approve(CURVE_STETH_POOL, _stETHAmount);
        
        // Swap stETH -> ETH via Curve (index 1 = stETH, index 0 = ETH)
        uint256 ethBefore = address(this).balance;
        ICurvePool(CURVE_STETH_POOL).exchange(1, 0, _stETHAmount, _minETHOut);
        uint256 ethReceived = address(this).balance - ethBefore;
        
        // Calculate proportion of principal being unstaked
        uint256 principalPortion = (_stETHAmount * stakedETHPrincipal) / stETHBalance;
        if (principalPortion > stakedETHPrincipal) principalPortion = stakedETHPrincipal;
        
        stakedETHPrincipal -= principalPortion;
        ethPrincipal += principalPortion;
        
        // Any extra ETH received is yield (fees taken at distribution)
        
        emit ETHUnstaked(_stETHAmount, ethReceived);
    }
    
    // ============ Yield Functions - Token Lending (Aave) ============
    
    /// @notice Lend tokens to Aave
    /// @param _token Token to lend (e.g., USDC, USDT, DAI)
    /// @param _amount Amount to lend
    /// @param _aToken The aToken address for this token
    function lendToken(address _token, uint256 _amount, address _aToken) 
        external onlyOwner notDistributed nonReentrant 
    {
        require(_amount > 0, "Zero amount");
        require(AAVE_POOL != address(0), "Aave not configured");
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "Insufficient balance");
        
        // Store aToken mapping
        tokenToAToken[_token] = _aToken;
        
        // Track principal
        uint256 fromPrincipal = _amount > tokenPrincipal[_token] ? tokenPrincipal[_token] : _amount;
        tokenPrincipal[_token] -= fromPrincipal;
        lentTokenPrincipal[_token] += fromPrincipal;
        
        // Approve and supply to Aave
        IERC20(_token).approve(AAVE_POOL, _amount);
        IAavePool(AAVE_POOL).supply(_token, _amount, address(this), 0);
        
        emit TokenLent(_token, _amount);
    }
    
    /// @notice Withdraw tokens from Aave
    /// @param _token Underlying token to withdraw
    /// @param _amount Amount to withdraw (use type(uint256).max for all)
    function withdrawFromAave(address _token, uint256 _amount) 
        external onlyOwner notDistributed nonReentrant 
    {
        require(AAVE_POOL != address(0), "Aave not configured");
        
        uint256 withdrawn = IAavePool(AAVE_POOL).withdraw(_token, _amount, address(this));
        
        // Calculate principal portion
        address aToken = tokenToAToken[_token];
        uint256 aTokenBalance = IAToken(aToken).balanceOf(address(this));
        uint256 totalLent = lentTokenPrincipal[_token];
        
        uint256 principalPortion;
        if (aTokenBalance == 0) {
            // Withdrawing everything
            principalPortion = totalLent;
        } else {
            // Proportional
            principalPortion = (withdrawn * totalLent) / (withdrawn + aTokenBalance);
        }
        
        if (principalPortion > lentTokenPrincipal[_token]) {
            principalPortion = lentTokenPrincipal[_token];
        }
        
        lentTokenPrincipal[_token] -= principalPortion;
        tokenPrincipal[_token] += principalPortion;
        
        emit TokenWithdrawnFromAave(_token, withdrawn);
    }
    
    // ============ Withdraw Functions (Owner) ============
    
    function withdrawETH(uint256 _amount) external onlyOwner notDistributed nonReentrant {
        require(_amount <= address(this).balance, "Insufficient balance");
        
        // Reduce principal tracking
        if (_amount <= ethPrincipal) {
            ethPrincipal -= _amount;
        } else {
            ethPrincipal = 0;
        }
        
        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH transfer failed");
        emit ETHWithdrawn(owner, _amount);
    }
    
    function withdrawToken(address _token, uint256 _amount) 
        external onlyOwner notDistributed nonReentrant 
    {
        // Reduce principal tracking
        if (_amount <= tokenPrincipal[_token]) {
            tokenPrincipal[_token] -= _amount;
        } else {
            tokenPrincipal[_token] = 0;
        }
        
        IERC20(_token).safeTransfer(owner, _amount);
        emit TokenWithdrawn(_token, owner, _amount);
    }
    
    // ============ Distribution Functions ============
    
    function triggerDistribution() external notDistributed nonReentrant {
        require(isClaimable(), "Not yet claimable");
        
        distributed = true;
        
        // Collect yield fees and calculate distributions
        _processETHDistribution();
        _processStETHDistribution();
        _processTokenDistributions();
        
        emit DistributionTriggered(msg.sender, block.timestamp);
    }
    
    function _processETHDistribution() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance == 0) return;
        
        // Calculate yield (balance - principal)
        uint256 yield = ethBalance > ethPrincipal ? ethBalance - ethPrincipal : 0;
        uint256 fee = (yield * YIELD_FEE_BP) / BASIS_POINTS_TOTAL;
        
        if (fee > 0) {
            (bool success, ) = treasury.call{value: fee}("");
            if (success) {
                emit YieldFeeCollected(address(0), fee);
            }
        }
        
        uint256 distributable = ethBalance - fee;
        
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address wallet = beneficiaries[i].wallet;
            uint256 bp = beneficiaries[i].basisPoints;
            claimableAmounts[wallet][address(0)] = (distributable * bp) / BASIS_POINTS_TOTAL;
        }
    }
    
    function _processStETHDistribution() internal {
        if (LIDO == address(0)) return;
        
        uint256 stETHBalance = ILido(LIDO).balanceOf(address(this));
        if (stETHBalance == 0) return;
        
        // For stETH, yield is automatically included in balance (rebasing)
        // Principal was tracked when staking
        uint256 yield = stETHBalance > stakedETHPrincipal ? stETHBalance - stakedETHPrincipal : 0;
        uint256 fee = (yield * YIELD_FEE_BP) / BASIS_POINTS_TOTAL;
        
        if (fee > 0) {
            ILido(LIDO).transfer(treasury, fee);
            emit YieldFeeCollected(LIDO, fee);
        }
        
        uint256 distributable = stETHBalance - fee;
        
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address wallet = beneficiaries[i].wallet;
            uint256 bp = beneficiaries[i].basisPoints;
            claimableAmounts[wallet][LIDO] = (distributable * bp) / BASIS_POINTS_TOTAL;
        }
    }
    
    function _processTokenDistributions() internal {
        for (uint256 j = 0; j < registeredTokens.length; j++) {
            address token = registeredTokens[j];
            if (token == LIDO) continue; // Already handled
            
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            
            // Check for aToken balance too
            address aToken = tokenToAToken[token];
            uint256 aTokenBalance = 0;
            if (aToken != address(0)) {
                aTokenBalance = IAToken(aToken).balanceOf(address(this));
                // Withdraw all from Aave first
                if (aTokenBalance > 0) {
                    IAavePool(AAVE_POOL).withdraw(token, type(uint256).max, address(this));
                    tokenBalance = IERC20(token).balanceOf(address(this));
                }
            }
            
            if (tokenBalance == 0) continue;
            
            // Calculate yield
            uint256 totalPrincipal = tokenPrincipal[token] + lentTokenPrincipal[token];
            uint256 yield = tokenBalance > totalPrincipal ? tokenBalance - totalPrincipal : 0;
            uint256 fee = (yield * YIELD_FEE_BP) / BASIS_POINTS_TOTAL;
            
            if (fee > 0) {
                IERC20(token).safeTransfer(treasury, fee);
                emit YieldFeeCollected(token, fee);
            }
            
            uint256 distributable = tokenBalance - fee;
            
            for (uint256 i = 0; i < beneficiaries.length; i++) {
                address wallet = beneficiaries[i].wallet;
                uint256 bp = beneficiaries[i].basisPoints;
                claimableAmounts[wallet][token] = (distributable * bp) / BASIS_POINTS_TOTAL;
            }
        }
    }
    
    // ============ Claim Functions ============
    
    function claimETH() external nonReentrant {
        require(distributed, "Distribution not triggered");
        
        uint256 ethAmount = claimableAmounts[msg.sender][address(0)];
        require(ethAmount > 0, "Nothing to claim");
        
        claimableAmounts[msg.sender][address(0)] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        emit ShareClaimed(msg.sender, address(0), ethAmount);
    }
    
    function claimTokens(address[] calldata _tokens) external nonReentrant {
        require(distributed, "Distribution not triggered");
        
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 amount = claimableAmounts[msg.sender][_tokens[i]];
            if (amount > 0) {
                claimableAmounts[msg.sender][_tokens[i]] = 0;
                IERC20(_tokens[i]).safeTransfer(msg.sender, amount);
                emit ShareClaimed(msg.sender, _tokens[i], amount);
            }
        }
    }
    
    function claimAll() external nonReentrant {
        require(distributed, "Distribution not triggered");
        
        // Claim ETH
        uint256 ethAmount = claimableAmounts[msg.sender][address(0)];
        if (ethAmount > 0) {
            claimableAmounts[msg.sender][address(0)] = 0;
            (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            emit ShareClaimed(msg.sender, address(0), ethAmount);
        }
        
        // Claim stETH if exists
        if (LIDO != address(0)) {
            uint256 stETHAmount = claimableAmounts[msg.sender][LIDO];
            if (stETHAmount > 0) {
                claimableAmounts[msg.sender][LIDO] = 0;
                ILido(LIDO).transfer(msg.sender, stETHAmount);
                emit ShareClaimed(msg.sender, LIDO, stETHAmount);
            }
        }
        
        // Claim all registered tokens
        for (uint256 i = 0; i < registeredTokens.length; i++) {
            address token = registeredTokens[i];
            if (token == LIDO) continue;
            
            uint256 amount = claimableAmounts[msg.sender][token];
            if (amount > 0) {
                claimableAmounts[msg.sender][token] = 0;
                IERC20(token).safeTransfer(msg.sender, amount);
                emit ShareClaimed(msg.sender, token, amount);
            }
        }
    }
    
    // ============ View Functions ============
    
    function isClaimable() public view returns (bool) {
        return block.timestamp > lastCheckIn + inactivityThreshold && !distributed;
    }
    
    function getTimeUntilClaimable() external view returns (uint256) {
        uint256 claimableAt = lastCheckIn + inactivityThreshold;
        if (block.timestamp >= claimableAt) return 0;
        return claimableAt - block.timestamp;
    }
    
    function getCheckInDeadline() external view returns (uint256) {
        return lastCheckIn + inactivityThreshold;
    }
    
    function getBeneficiaries() external view returns (Beneficiary[] memory) {
        return beneficiaries;
    }
    
    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaries.length;
    }
    
    function getRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }
    
    function getYieldStatus() external view returns (
        uint256 ethBalance,
        uint256 _ethPrincipal,
        uint256 stETHBalance,
        uint256 _stakedPrincipal,
        uint256 estimatedETHYield,
        uint256 estimatedStETHYield
    ) {
        ethBalance = address(this).balance;
        _ethPrincipal = ethPrincipal;
        stETHBalance = LIDO != address(0) ? ILido(LIDO).balanceOf(address(this)) : 0;
        _stakedPrincipal = stakedETHPrincipal;
        estimatedETHYield = ethBalance > ethPrincipal ? ethBalance - ethPrincipal : 0;
        estimatedStETHYield = stETHBalance > stakedETHPrincipal ? stETHBalance - stakedETHPrincipal : 0;
    }
    
    // ============ Internal Functions ============
    
    function _setBeneficiaries(Beneficiary[] memory _beneficiaries) internal {
        require(_beneficiaries.length > 0, "Need at least one beneficiary");
        require(_beneficiaries.length <= MAX_BENEFICIARIES, "Too many beneficiaries");
        
        delete beneficiaries;
        uint256 totalBasisPoints = 0;
        
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            require(_beneficiaries[i].wallet != address(0), "Invalid beneficiary");
            require(_beneficiaries[i].wallet != owner, "Owner cannot be beneficiary");
            require(_beneficiaries[i].basisPoints > 0, "Share must be > 0");
            
            totalBasisPoints += _beneficiaries[i].basisPoints;
            beneficiaries.push(_beneficiaries[i]);
        }
        
        require(totalBasisPoints == BASIS_POINTS_TOTAL, "Shares must total 100%");
    }
    
    // ============ Receive ETH ============
    
    receive() external payable {
        ethPrincipal += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }
    
    fallback() external payable {
        ethPrincipal += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }
}
