import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@oasisprotocol/sapphire-hardhat";
import * as dotenv from "dotenv";

dotenv.config();


const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    sapphireTestnet: {
      url: "https://testnet.sapphire.oasis.dev",
      accounts: process.env.PRIVATE_KEY_TESTNET ? [process.env.PRIVATE_KEY_TESTNET] : [],
      chainId: 23295
    },
    sapphireMainnet: {
      url: "https://sapphire.oasis.io",
      accounts: process.env.PRIVATE_KEY_MAINNET ? [process.env.PRIVATE_KEY_MAINNET] : [],
      chainId: 23294
    },
    sapphireLocalnet: {
      url: "http://localhost:8545",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 0x5afd
    }
  }
};

export default config; 