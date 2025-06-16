import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@oasisprotocol/sapphire-hardhat"; // comment out for deployment
import * as dotenv from "dotenv";

dotenv.config();

const TEST_HDWALLET = {
  mnemonic: "test test test test test test test test test test test junk",
  path: "m/44'/60'/0'/0",
  initialIndex: 0,
  count: 20,
  passphrase: "",
};


const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: { // https://hardhat.org/metamask-issue.html
      chainId: 1337,
    },
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
      //  docker run -it -p8544-8548:8544-8548 --platform linux/x86_64 ghcr.io/oasisprotocol/sapphire-localnet
      url: "http://localhost:8545",
      accounts: TEST_HDWALLET,
      chainId: 0x5afd
    }
  }
};

export default config; 
