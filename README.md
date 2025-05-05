# Trustless Bridge Contracts

Smart contracts for the Trustless Bridge protocol.

## Prerequisites

- Node.js (v16 or later)
- npm or yarn
- Hardhat

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd trustless-bridge-contracts
```

2. Install dependencies:
```bash
npm install
```

3. Create a `.env` file in the root directory and add your environment variables:
```bash
cp .env.example .env
```

Edit the `.env` file with your configuration:
```
RPC_URL=<your-rpc-url>
PRIVATE_KEY=<your-private-key>
```

## Hardhat Commands

### Compile Contracts
```bash
npx hardhat compile
```

### Run Tests
```bash
npx hardhat test
```

### Deploy Contracts

#### To Sapphire Testnet
```bash
npx hardhat run scripts/deploy.ts --network sapphireTestnet
```

#### To Sapphire Mainnet
```bash
npx hardhat run scripts/deploy.ts --network sapphireMainnet
```

#### To Local Network
```bash
npx hardhat run scripts/deploy.ts --network sapphireLocalnet
```

### Run Local Network
```bash
npx hardhat node
```

### Verify Contracts
```bash
npx hardhat verify --network sapphireTestnet <contract-address> <constructor-arguments>
```


## Verify contract

To verify on Sourcify.eth:

- Select: Import from solidity JSON
- Set compiler the same as hardhat.config
- choose file: leave blank
- In drag and drop section you select all JSON files inside artifacts/build-info
- You wait for it to load then under each contract you set address and chain

## Network Configuration

The project is configured to work with the following networks:

- **Sapphire Testnet** (chainId: 23295)
  - RPC URL: https://testnet.sapphire.oasis.dev
- **Sapphire Mainnet** (chainId: 23294)
  - RPC URL: https://sapphire.oasis.io
- **Local Network** (chainId: 0x5afd)
  - RPC URL: http://localhost:8545

## Project Structure

```
├── contracts/           # Solidity smart contracts
│   ├── tBTC.sol        # Main TBTC contract
│   └── utils/          # Utility contracts
├── scripts/            # Deployment and utility scripts
├── test/              # Test files
├── hardhat.config.ts  # Hardhat configuration
└── package.json       # Project dependencies
```

## License

[License Type]
