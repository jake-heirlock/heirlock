# Heirlock

Non-custodial inheritance vaults for Ethereum and EVM chains.

## What is Heirlock?

Heirlock lets you set up secure inheritance for your crypto assets without giving up control of your keys. Designate beneficiaries, set an inactivity threshold, and your assets automatically become claimable if you stop checking in.

**No tokens to buy. No hardware to manage. No complexity.**

## How It Works

1. **Create a Vault** - Deploy your personal vault through the factory contract. Set your beneficiaries and their share percentages, plus your inactivity threshold (1 month to 2 years).

2. **Fund Your Vault** - Send ETH and tokens to your vault address. Register which tokens should be included in distribution.

3. **Check In Periodically** - A simple transaction confirms you're still active and resets the timer. Takes seconds.

4. **Automatic Inheritance** - If you miss your check-in window, beneficiaries can trigger distribution and claim their shares. No keys shared, ever.

## Key Features

| Feature | Description |
|---------|-------------|
| **Non-custodial** | Your keys never leave your wallet. We can't access your funds. Ever. |
| **Configurable timers** | Set your own inactivity threshold from 1 month to 2 years |
| **Multiple beneficiaries** | Split assets between up to 10 wallets with custom percentages |
| **Multi-token support** | Supports ETH and any ERC20 token (up to 50 per vault) |
| **Immutable logic** | Contract rules can't be changed by anyone, including us |
| **Optional yield** | Earn yield on your assets via Lido (ETH) and Aave (stablecoins) |

## Vault Types

### Basic Vault (0.01 ETH)

Simple inheritance vault with core functionality:
- Deposit ETH and ERC20 tokens
- Set beneficiaries with custom splits
- Periodic check-in to prove activity
- Automatic distribution after inactivity threshold

### Yield Vault (0.02 ETH)

Everything in Basic, plus optional yield generation:
- Stake ETH via Lido (earn ~3-4% APY in stETH)
- Lend stablecoins via Aave (variable APY)
- 10% protocol fee on yield only (not principal)
- Instant unstaking via Curve (when available)

## Contracts

### Core Contracts

| Contract | Description |
|----------|-------------|
| `HeirlockVault.sol` | Basic inheritance vault for individual users |
| `HeirlockVaultYield.sol` | Yield-enabled vault with Lido/Aave integration |
| `HeirlockFactory.sol` | Factory for deploying both vault types |
| `HeirlockRegistry.sol` | Optional registry for vault discovery and notifications |

### Deployed Addresses

| Network | Factory | Registry |
|---------|---------|----------|
| Ethereum Mainnet | `TBD` | `TBD` |
| Sepolia Testnet | `TBD` | `TBD` |
| Base | `TBD` | `TBD` |
| Arbitrum | `TBD` | `TBD` |
| Polygon | `TBD` | `TBD` |

## Development

### Prerequisites

- Node.js 18+
- npm or yarn

### Setup

```bash
# Clone the repo
git clone https://github.com/jake-heirlock/heirlock.git
cd heirlock/contracts

# Install dependencies
npm install

# Copy environment file
cp .env.example .env
# Edit .env with your values
```

### Commands

```bash
# Compile contracts
npm run compile

# Run tests
npm test

# Run tests with gas reporting
npm run test:gas

# Run test coverage
npm run test:coverage

# Start local node
npm run node

# Deploy to local
npm run deploy:local

# Deploy to testnet
npm run deploy:sepolia
npm run deploy:base-sepolia

# Deploy to mainnet (be careful!)
npm run deploy:mainnet
npm run deploy:base
npm run deploy:arbitrum
```

### Environment Variables

Create a `.env` file based on `.env.example`:

```bash
# Treasury address for fees
TREASURY_ADDRESS=0x...

# RPC URLs
SEPOLIA_RPC_URL=https://...
MAINNET_RPC_URL=https://...

# Deployer private key
PRIVATE_KEY=...

# Block explorer API keys
ETHERSCAN_API_KEY=...
BASESCAN_API_KEY=...
```

## Project Structure

```
contracts/
├── contracts/
│   ├── HeirlockVault.sol           # Basic vault
│   ├── HeirlockVaultYield.sol      # Yield-enabled vault
│   ├── HeirlockFactory.sol         # Vault factory
│   ├── HeirlockRegistry.sol        # Discovery registry
│   ├── interfaces/
│   │   ├── IHeirlockVault.sol      # Vault interface
│   │   └── IYieldInterfaces.sol    # Lido/Aave interfaces
│   └── mocks/
│       └── MockERC20.sol           # Test token
├── test/
│   └── Heirlock.test.ts            # Test suite
├── scripts/
│   └── deploy.ts                   # Deployment script
├── hardhat.config.ts
├── package.json
└── .env.example
```

## Architecture

### Vault Lifecycle

```
┌─────────────────┐
│  Create Vault   │  User pays 0.01 ETH (basic) or 0.02 ETH (yield)
│  via Factory    │  Sets beneficiaries, threshold
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Fund Vault    │  User deposits ETH/tokens
│                 │  Registers tokens for distribution
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Active Use    │◄─────┐
│                 │      │ Check-in resets timer
└────────┬────────┘      │
         │               │
         ▼               │
┌─────────────────┐      │
│  Check In?      │──Yes─┘
│                 │
└────────┬────────┘
         │ No (threshold passed)
         ▼
┌─────────────────┐
│   Claimable     │  Anyone can trigger distribution
│                 │  Beneficiaries claim their shares
└─────────────────┘
```

### Security Model

- **No admin keys**: Factory and vaults have zero privileged functions
- **Isolated vaults**: Each user gets their own contract; one compromise doesn't affect others
- **Immutable logic**: No upgradeable proxies, no owner backdoors
- **Pull pattern**: Beneficiaries claim their shares (safer than push)
- **Reentrancy guards**: On all external transfer functions

## Fee Structure

| Action | Fee | Recipient |
|--------|-----|-----------|
| Create Basic Vault | 0.01 ETH | Treasury |
| Create Yield Vault | 0.02 ETH | Treasury |
| Yield (Lido/Aave) | 10% of profits | Treasury |
| Check-in | Gas only | - |
| Distribution | Gas only | - |
| Claims | Gas only | - |

## Yield Integration

### ETH Staking (Lido)

Yield vaults can stake ETH to Lido to earn staking rewards:

```solidity
// Stake ETH
vault.stakeETH(amount);

// Unstake via Curve (instant, may have slippage)
vault.unstakeETH(stETHAmount, minETHOut);
```

### Token Lending (Aave)

Yield vaults can lend stablecoins to Aave:

```solidity
// Lend USDC to Aave
vault.lendToken(usdcAddress, amount, aUsdcAddress);

// Withdraw from Aave
vault.withdrawFromAave(usdcAddress, amount);
```

### Yield Fee Calculation

The protocol takes 10% of yield, not principal:

```
Deposit: 10 ETH
After 1 year staking: 10.4 ETH (4% yield)
Yield: 0.4 ETH
Protocol fee: 0.04 ETH (10% of yield)
Beneficiaries receive: 10.36 ETH
```

## Registry

The optional `HeirlockRegistry` provides:

- **Beneficiary indexing**: Discover vaults you're entitled to
- **Deadline tracking**: Find vaults approaching check-in deadline
- **Notification support**: Powers reminder systems

```solidity
// Register vault for indexing
registry.registerVault(vaultAddress);

// Find vaults where you're a beneficiary
registry.getVaultsForBeneficiary(myAddress);

// Get vaults near deadline (for notifications)
registry.getVaultsNearDeadline(7 days);
```

## Security

⚠️ **This code has not been audited. Use at your own risk.**

### Known Risks

- Smart contract bugs (despite testing)
- Yield protocol risks (Lido, Aave, Curve)
- stETH depeg risk (rare but possible)
- User error (wrong beneficiary addresses, forgetting to check in)

### Bug Bounty

If you find a vulnerability, please report it responsibly:
- Email: security@heirlock.xyz
- Do not disclose publicly until fixed

## Roadmap

- [x] Basic vault contracts
- [x] Yield vault with Lido/Aave
- [x] Multi-network deployment support
- [ ] Professional audit
- [ ] Mainnet deployment
- [ ] Email/SMS check-in reminders
- [ ] Mobile app with one-tap check-in
- [ ] NFT vault support
- [ ] Multi-sig beneficiary support

## Contributing

Contributions are welcome! Please:

1. Open an issue first to discuss changes
2. Fork the repo and create a feature branch
3. Write tests for new functionality
4. Submit a PR with clear description

## License

[MIT](LICENSE)

## Links

- Website: [heirlock.xyz](https://heirlock.xyz)
- GitHub: [github.com/jake-heirlock/heirlock](https://github.com/jake-heirlock/heirlock)
- Email: hello@heirlock.xyz
