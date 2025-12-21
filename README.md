# Heirlock

Non-custodial inheritance vaults for Ethereum and EVM chains.

## What is Heirlock?

Heirlock lets you set up secure inheritance for your crypto assets without giving up control of your keys. Designate beneficiaries, set an inactivity threshold, and your assets automatically become claimable if you stop checking in.

## How It Works

1. **Create a Vault** - Deploy your personal vault through the factory contract. Set your beneficiaries and their share percentages, plus your inactivity threshold (1 month to 2 years).

2. **Fund Your Vault** - Send ETH and tokens to your vault address. Register which tokens should be included in distribution.

3. **Check In Periodically** - A simple transaction confirms you're still active and resets the timer. Takes seconds.

4. **Automatic Inheritance** - If you miss your check-in window, beneficiaries can trigger distribution and claim their shares. No keys shared, ever.

## Key Features

- **Non-custodial**: Your keys never leave your wallet. We can't access your funds. Ever.
- **Configurable timers**: Set your own inactivity threshold from 1 month to 2 years.
- **Multiple beneficiaries**: Split assets between multiple wallets with custom percentages.
- **Multi-token support**: Supports ETH and any ERC20 token.
- **Immutable logic**: Contract rules can't be changed by anyone, including us.

## Contracts

| Network | Factory | Registry |
|---------|---------|----------|
| Ethereum Mainnet | `TBD` | `TBD` |
| Sepolia Testnet | `TBD` | `TBD` |
| Polygon | `TBD` | `TBD` |
| Arbitrum | `TBD` | `TBD` |
| Base | `TBD` | `TBD` |

## Development

```bash
# Clone the repo
git clone https://github.com/yourusername/heirlock.git
cd heirlock

# Install dependencies
npm install

# Run tests
npm test

# Run local node
npm run node

# Deploy to local
npm run deploy:local

# Deploy to testnet
npm run deploy:sepolia
```

## Project Structure

```
heirlock/
├── apps/
│   ├── web/                  # Landing page
│   └── app/                  # Main dApp
├── packages/
│   └── contracts/            # Smart contracts
│       ├── contracts/
│       ├── scripts/
│       ├── test/
│       └── deployments/
└── docs/
```

## Security

This code has not been audited. Use at your own risk.

If you find a vulnerability, please report it responsibly by emailing security@heirlock.xyz.

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

## License

[MIT](LICENSE)
