# Heirlock Security

## Audit Status

**This code has not been audited.** Use at your own risk.

## Security Properties

### Non-Custodial
- No admin keys exist anywhere in the protocol
- Factory has no privileged functions
- Vault owner has sole control until distribution
- Private keys never leave user wallets

### Immutable
- No upgradeable proxy pattern
- Contract logic cannot be modified after deployment
- No governance or admin override

### Isolated
- Each vault is an independent contract
- No shared state between vaults
- Single vault compromise does not affect others

## Threat Model

### Threats Mitigated

| Threat | Mitigation |
|--------|------------|
| Reentrancy attacks | ReentrancyGuard on all external calls |
| Admin key compromise | No admin keys exist |
| Upgrade attacks | No upgrade mechanism |
| Front-running distribution | Pull pattern for claims |
| Beneficiary DoS | Each beneficiary claims independently |

### Known Limitations

| Limitation | Description |
|------------|-------------|
| Token compatibility | Only standard ERC20 tokens supported. Fee-on-transfer or rebasing tokens may not work correctly. |
| Gas costs | Distribution and claims scale with number of tokens and beneficiaries |
| Timing attacks | Block timestamp used for check-ins (minor miner manipulation possible) |
| Lost beneficiary keys | If a beneficiary loses their keys, their share is locked forever |

### Out of Scope

- Social engineering (owner tricked into bad beneficiary config)
- Compromised owner private key
- Network-level attacks (chain reorgs, 51% attacks)

## Best Practices for Users

### For Vault Owners

1. **Verify contract addresses** - Always verify you're interacting with the official factory
2. **Test with small amounts first** - Create a test vault before putting significant funds
3. **Set realistic thresholds** - Balance between security (longer) and practicality (shorter)
4. **Multiple check-in methods** - Have backup ways to check in if primary method fails
5. **Inform beneficiaries** - Make sure they know about the vault and how to claim

### For Beneficiaries

1. **Verify vault legitimacy** - Check the vault was created by the official factory
2. **Monitor deadlines** - Know when vaults you're a beneficiary of might become claimable
3. **Secure your keys** - If you lose access, your share is lost

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it responsibly:

1. **Do not** disclose publicly until fixed
2. Email: security@heirlock.xyz
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Contract Verification

All deployed contracts are verified on block explorers. Always verify:

1. Source code matches what's in this repo
2. Contract address matches official deployment
3. No proxy contract between you and the logic

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| OpenZeppelin Contracts | 5.0.0 | SafeERC20, ReentrancyGuard |
| Solidity | 0.8.20 | Compiler |

OpenZeppelin contracts are battle-tested and widely used in DeFi.
