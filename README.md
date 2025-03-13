# Clober Futures Market

[![CI Status](https://github.com/clober-dex/futures-market/actions/workflows/test.yml/badge.svg)](https://github.com/clober-dex/futures-market/actions/workflows/test.yml)
[![Website](https://img.shields.io/badge/website-futures.clober.io-blue)](https://futures.clober.io/future)

## Overview

**Clober Futures Market** is a decentralized protocol designed to facilitate **Non-Deliverable Forward (NDF)** contracts on EVM-compatible blockchains.  
In traditional finance, an NDF is a type of forward contract where there is **no physical delivery of the underlying asset**—instead, profits and losses are settled in a widely accepted currency (e.g., USD). This project recreates that mechanism on-chain, allowing users to hedge or speculate on various assets using a **cash-settled** approach.

---

## Install

### Prerequisites
- We use [Forge Foundry](https://github.com/foundry-rs/foundry) for **testing**. Follow the [Foundry installation guide](https://github.com/foundry-rs/foundry#installation).
- **Node.js** and **npm** (Node Package Manager) are required. You can download and install them from the [official Node.js website](https://nodejs.org/).

### Installing from source

```bash
git clone https://github.com/clober-dex/futures-market && cd futures-market
forge install
npm install
```

## Usage

### Build
```bash
forge build
```

### Tests
```bash
forge test
```

### Linting

```bash
forge fmt
```

## Deployments

For the most up-to-date deployment addresses, please check the [`deployments/`](./deployments/) directory.

### Monad Testnet (Chain ID: 10143)
| Contract | Address | Explorer Link |
|----------|---------|---------------|
| FuturesMarket | `0x86Add33C407dB62b44E08BC326b4F5CD1eBA575f` | [View on Monad Explorer](https://testnet.monadexplorer.com/address/0x86Add33C407dB62b44E08BC326b4F5CD1eBA575f) |
| PythOracle | `0x51b7bf333aa6425B951da4C42105d94F68F6e80E` | [View on Monad Explorer](https://testnet.monadexplorer.com/address/0x51b7bf333aa6425B951da4C42105d94F68F6e80E) |

## Project Structure

```
futures-market/
├── src/             # Smart contract source files
├── test/            # Test files
├── script/          # Deployment and other scripts
├── deployments/     # Deployed contract addresses
└── lib/             # Dependencies and external libraries
```

The project follows a standard Foundry project structure:
- `src/`: Contains the core smart contract implementations
- `test/`: Contains the test suite for the contracts
- `script/`: Contains deployment scripts and other utilities
- `deployments/`: Contains deployed contract addresses for different networks
- `lib/`: Contains project dependencies managed by Forge

## Architecture & Technical Implementation

### Overview
Futures Market is a decentralized futures trading protocol running on EVM-compatible chains. It adopts a modularized structure using the Diamond Proxy pattern and utilizes Pyth Network's Pull Oracle for secure and efficient oracle data processing.

### Technologies Used
1. **Diamond Proxy ([EIP-2535](https://eips.ethereum.org/EIPS/eip-2535))**
   - Modularized smart contract structure
   - Upgradeable contract design
   - Gas-optimized function execution

2. **[CreateX](https://github.com/pcaversaccio/createx)**
   - Optimized contract deployment
   - Deterministic address generation

3. **[IERC3156 Flashloan](https://eips.ethereum.org/EIPS/eip-3156)**
   - Liquidity utilization optimization
   - Complex trading strategy support

4. **[Permit](https://eips.ethereum.org/EIPS/eip-2612)**
   - Gasless approvals
   - Enhanced user experience

5. **Multicall**
   - Execute multiple operations in a single transaction
   - Gas cost reduction

### External Dependencies

#### Pyth Network
We integrate [Pyth Network](https://pyth.network/) for reliable price feeds using their pull oracle mechanism. For detailed implementation, check out the [Pyth documentation](https://docs.pyth.network/price-feeds/pull-updates).

### Design Choices

#### Diamond Proxy Pattern (EIP-2535)
- Enhanced maintainability through modularized contract structure
- Selective feature upgradeability
- Prevention of storage collisions
- Gas-efficient function calls

#### Pull Oracle vs Push Oracle
Reasons for choosing Pull Oracle:
- On-demand data updates
- Gas cost optimization
- Reduced network load
- High reliability and accuracy
- Usage-based cost structure

## How It Works

### Basic Workflow

1. **Market Creation**
   - Markets are created with specific parameters:
     - Asset ID and Collateral token
     - Expiration date
     - LTV (Loan-to-Value) ratio
     - Liquidation threshold
     - Minimum debt amount

2. **Position Management**
   - **Opening a Position**:
     1. Deposit collateral into the market
     2. Mint debt tokens to create leverage
     3. Monitor position's health ratio
   
   - **Trading Hours Restriction**:
     - For stock futures, position minting, withdrawal, and liquidation are only available during stock market trading hours
     - This restriction ensures alignment with traditional stock market operations
     - Other operations remain available 24/7

   - **Managing Risk**:
     - Add more collateral to avoid liquidation
     - Burn debt tokens to reduce exposure
     - Monitor oracle price feeds

3. **Settlement & Position Closing**
   - **Settlement**: 
     - At expiry, market is settled at the oracle price
     - Settlement price determines the final PnL for all positions
   
   - **Closing Options**:
     - **Close**: Receive PnL in settlement currency (profit or loss based on position)
     - **Redeem**: Exchange debt tokens for collateral at settlement price
   
   - **Liquidation**: 
     - Positions below liquidation threshold can be liquidated before settlement
     - Liquidators can cover debt and receive collateral at a discount

## Risks & Disclaimers

### Trading Risks
- **Liquidation Risk**: Positions are liquidated if they fall below the liquidation threshold
- **Oracle Risk**: 
  - Price feed delays or failures could affect position management
  - Pyth Network oracle reliability is critical for settlement
- **Market Risk**:
  - Volatile market conditions may cause significant losses
- **Smart Contract Risk**: 
  - Despite audits, smart contract vulnerabilities may exist
  - Interaction with multiple protocols increases complexity

### Important Notes
- This protocol is designed for experienced traders familiar with futures trading
- Understand the liquidation mechanism
- Monitor position health ratio regularly
- Test with small amounts first to understand the system
- Past performance does not guarantee future results

## License

The source code in `src/` is licensed under GPL-2.0-or-later.

## Contributing

We welcome contributions from the community! Please follow these steps:

1. Fork the repository
2. Create a new branch for your feature
3. Submit a Pull Request with a clear description
4. Follow our code style and include tests

For bug reports or feature requests, please open an issue on GitHub.
