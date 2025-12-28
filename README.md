# STX Escrow 🔐

A trustless escrow system for secure peer-to-peer transactions on Stacks blockchain. Enable safe trades without intermediaries.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Built on Stacks](https://img.shields.io/badge/Built%20on-Stacks-5546FF)](https://stacks.co)

## Overview

STX Escrow provides a decentralized escrow service for STX and SIP-010 tokens. It enables trustless transactions between parties who don't know each other, with built-in dispute resolution.

## Features

- 🔒 **Trustless** - Smart contract holds funds, no third party needed
- ⚡ **Fast** - Instant release upon agreement
- 🛡️ **Secure** - Multi-sig release and time-locked refunds
- 💰 **Multi-Asset** - Supports STX and any SIP-010 token
- ⚖️ **Disputes** - Built-in arbitration system
- 📱 **User-Friendly** - Simple create, fund, release flow

## Use Cases

- **P2P Trading** - Buy/sell crypto safely
- **Freelance Work** - Payment upon delivery
- **NFT Sales** - Secure NFT-for-STX swaps
- **Service Agreements** - Milestone-based payments
- **Cross-chain Swaps** - BTC-STX atomic swaps

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   BUYER     │     │   ESCROW    │     │   SELLER    │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │ 1. Create Escrow  │                   │
       │──────────────────>│                   │
       │                   │                   │
       │ 2. Deposit STX    │                   │
       │──────────────────>│                   │
       │                   │                   │
       │                   │ 3. Deliver goods  │
       │                   │<──────────────────│
       │                   │                   │
       │ 4. Confirm receipt│                   │
       │──────────────────>│                   │
       │                   │                   │
       │                   │ 5. Release funds  │
       │                   │──────────────────>│
       │                   │                   │
```

## Smart Contracts

### escrow-core.clar
Main escrow logic with create, fund, release, refund functions.

### escrow-arbitration.clar
Dispute resolution with arbiter voting and evidence submission.

### escrow-milestone.clar
Multi-milestone escrows for complex projects.

## Quick Start

### Create an Escrow

```clarity
;; Create escrow with seller and amount
(contract-call? .escrow-core create-escrow
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 ;; seller
  u1000000 ;; 1 STX in micro-STX
  u144 ;; 1 day timeout (blocks)
  "Buying digital art"
)
```

### Fund the Escrow

```clarity
;; Deposit funds into escrow
(contract-call? .escrow-core fund-escrow u1) ;; escrow ID
```

### Release Funds

```clarity
;; Buyer confirms receipt, releases funds to seller
(contract-call? .escrow-core release-escrow u1)
```

### Request Refund

```clarity
;; Seller didn't deliver, buyer requests refund
(contract-call? .escrow-core request-refund u1)
```

## Escrow States

| State | Description |
|-------|-------------|
| `created` | Escrow created, waiting for funding |
| `funded` | Buyer deposited funds |
| `released` | Funds sent to seller |
| `refunded` | Funds returned to buyer |
| `disputed` | Under arbitration |
| `expired` | Timeout reached, auto-refund available |

## Fees

| Action | Fee |
|--------|-----|
| Create Escrow | Free |
| Successful Release | 0.5% |
| Refund | Free |
| Dispute Filing | 1 STX |
| Arbitration | 2% of amount |

## Security Features

- **Time Locks** - Configurable timeout for auto-refund
- **Multi-Sig** - Both parties must agree for non-standard actions
- **Amount Limits** - Configurable min/max escrow amounts
- **Pause Mechanism** - Emergency circuit breaker

## Installation

```bash
# Clone the repository
git clone https://github.com/serayd61/stx-escrow.git
cd stx-escrow

# Run tests
clarinet test

# Deploy to testnet
clarinet deployments apply -p testnet
```

## API Reference

### Read Functions

| Function | Description |
|----------|-------------|
| `get-escrow(id)` | Get escrow details |
| `get-escrow-status(id)` | Get current status |
| `get-user-escrows(user)` | Get all escrows for a user |
| `get-escrow-count()` | Total escrows created |

### Write Functions

| Function | Description |
|----------|-------------|
| `create-escrow(seller, amount, timeout, memo)` | Create new escrow |
| `fund-escrow(id)` | Deposit funds |
| `release-escrow(id)` | Release funds to seller |
| `request-refund(id)` | Request refund as buyer |
| `cancel-escrow(id)` | Cancel unfunded escrow |

## Roadmap

- [x] Core escrow functionality
- [x] STX support
- [ ] SIP-010 token support
- [ ] NFT escrow
- [ ] Multi-milestone escrows
- [ ] Arbiter DAO
- [ ] Mobile app integration

## Contributing

Contributions welcome! Please read our contributing guidelines.

## License

MIT © [serayd61](https://github.com/serayd61)

## Related

- [OpenZeppelin Escrow](https://docs.openzeppelin.com/contracts/4.x/api/utils#Escrow)
- [Stacks.js](https://github.com/hirosystems/stacks.js)

