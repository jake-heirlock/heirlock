// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILido
 * @notice Interface for Lido stETH staking
 */
interface ILido {
    /// @notice Submit ETH for staking, receive stETH
    /// @param _referral Referral address (can be address(0))
    /// @return Amount of stETH minted
    function submit(address _referral) external payable returns (uint256);
    
    /// @notice Get stETH balance (rebasing)
    function balanceOf(address _account) external view returns (uint256);
    
    /// @notice Transfer stETH
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    
    /// @notice Approve stETH spending
    function approve(address _spender, uint256 _amount) external returns (bool);
}

/**
 * @title IWstETH
 * @notice Interface for wrapped stETH (non-rebasing)
 */
interface IWstETH {
    /// @notice Wrap stETH to wstETH
    function wrap(uint256 _stETHAmount) external returns (uint256);
    
    /// @notice Unwrap wstETH to stETH
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    
    /// @notice Get wstETH balance
    function balanceOf(address _account) external view returns (uint256);
    
    /// @notice Transfer wstETH
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    
    /// @notice Get stETH amount for wstETH amount
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    
    /// @notice Get wstETH amount for stETH amount
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}

/**
 * @title IPool (Aave V3)
 * @notice Interface for Aave V3 lending pool
 */
interface IAavePool {
    /// @notice Supply assets to Aave
    /// @param asset The address of the underlying asset
    /// @param amount The amount to supply
    /// @param onBehalfOf The address that will receive the aTokens
    /// @param referralCode Referral code (use 0)
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
    
    /// @notice Withdraw assets from Aave
    /// @param asset The address of the underlying asset
    /// @param amount The amount to withdraw (use type(uint256).max for full balance)
    /// @param to The address that will receive the underlying
    /// @return The final amount withdrawn
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

/**
 * @title IAToken
 * @notice Interface for Aave aTokens
 */
interface IAToken {
    /// @notice Get aToken balance (includes accrued interest)
    function balanceOf(address _account) external view returns (uint256);
    
    /// @notice Get the underlying asset address
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    
    /// @notice Transfer aTokens
    function transfer(address _recipient, uint256 _amount) external returns (bool);
}

/**
 * @title ICurvePool
 * @notice Interface for Curve stETH/ETH pool (for instant unstaking)
 */
interface ICurvePool {
    /// @notice Exchange tokens
    /// @param i Index of input token (0 = ETH, 1 = stETH)
    /// @param j Index of output token
    /// @param dx Amount of input token
    /// @param min_dy Minimum output amount
    /// @return Amount received
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);
    
    /// @notice Get expected output amount
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}
