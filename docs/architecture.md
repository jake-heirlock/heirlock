# Heirlock Architecture

## Overview

Heirlock uses a factory pattern where each user deploys their own isolated vault contract. This provides security isolation, true ownership, and verifiability.

## Contracts

### HeirlockFactory

The entry point for creating new vaults. Has no admin functions or special permissions.

**Key Functions:**
- `createVault(beneficiaries, threshold)` - Deploys a new vault for the caller

**State:**
- Tracks all vaults ever created
- Indexes vaults by owner address

### HeirlockVault

Individual inheritance vault owned by a single user.

**Key Functions:**

Owner functions (before distribution):
- `checkIn()` - Resets the inactivity timer
- `registerToken(token)` / `registerTokens(tokens)` - Add tokens to distribution
- `unregisterToken(token)` - Remove token from distribution
- `updateBeneficiaries(beneficiaries)` - Change beneficiaries and shares
- `updateThreshold(seconds)` - Change inactivity threshold (resets timer)
- `withdrawETH(amount)` / `withdrawToken(token, amount)` - Withdraw funds

Anyone (after threshold passed):
- `triggerDistribution()` - Lock in shares for beneficiaries

Beneficiaries (after distribution triggered):
- `claimETH()` - Claim ETH share
- `claimTokens(tokens)` - Claim specific token shares
- `claimAll()` - Claim everything

**State:**
- Owner address (immutable)
- Last check-in timestamp
- Inactivity threshold
- Beneficiaries array with basis points
- Registered tokens for distribution
- Claimable amounts after distribution

### HeirlockRegistry

Optional contract for indexing and notifications. Vaults can register here to enable:
- Beneficiary discovery (find vaults where you're a beneficiary)
- Deadline monitoring (for notification services)

## Security Model

### Non-Custodial
- Owner has full control until distribution triggers
- No admin keys anywhere in the system
- Factory cannot modify or access vaults

### Immutable
- No upgradeable proxies
- Contract logic cannot be changed after deployment
- Only owner can modify their vault settings

### Isolated
- Each user has their own vault contract
- One vault compromise doesn't affect others
- No shared state between vaults

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     SETUP PHASE                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  User ──► Factory.createVault() ──► New Vault deployed      │
│                                                              │
│  User ──► Send ETH/tokens to Vault                          │
│                                                              │
│  User ──► Vault.registerTokens()                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                     ACTIVE PHASE                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  User ──► Vault.checkIn() ──► Timer resets                  │
│                                                              │
│  User can:                                                   │
│    • Withdraw funds anytime                                  │
│    • Update beneficiaries                                    │
│    • Update threshold                                        │
│    • Add/remove tokens                                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ (User misses check-in deadline)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   CLAIMABLE PHASE                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Anyone ──► Vault.triggerDistribution()                     │
│                                                              │
│  Shares calculated and locked for each beneficiary          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    CLAIM PHASE                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Beneficiary1 ──► Vault.claimAll() ──► Receives share       │
│                                                              │
│  Beneficiary2 ──► Vault.claimAll() ──► Receives share       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| MIN_THRESHOLD | 30 days | Minimum inactivity period |
| MAX_THRESHOLD | 730 days | Maximum inactivity period (2 years) |
| MAX_BENEFICIARIES | 10 | Maximum beneficiaries per vault |
| MAX_TOKENS | 50 | Maximum registered tokens per vault |
| BASIS_POINTS_TOTAL | 10000 | 100% in basis points |

## Gas Considerations

- Vault deployment: ~1.5M gas
- Check-in: ~30K gas
- Token registration: ~50K gas per token
- Trigger distribution: Variable based on beneficiaries and tokens
- Claim: ~50K gas for ETH, ~60K per token
