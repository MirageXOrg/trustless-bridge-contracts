import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Create a bytes21 value (21 bytes = 42 hex characters)
  const roflAppID = ethers.zeroPadValue("0x0102030405060708090a0b0c0d0e0f101112131415", 21);
  const oracle = process.env.ORACLE_ADDRESS || "0x704bA7cA2B5e649cd0b77Fd0c2568cdb9C033048";

  let bitcoinUtilsAddress: string;

  // Check if BitcoinUtils address is set in environment
  if (process.env.BITCOIN_UTILS_ADDRESS) {
    bitcoinUtilsAddress = process.env.BITCOIN_UTILS_ADDRESS;
    console.log("Using existing BitcoinUtils at:", bitcoinUtilsAddress);
  } else {
    // Deploy BitcoinUtils library if no address is provided
    const BitcoinUtils = await ethers.getContractFactory("BitcoinUtils");
    const bitcoinUtils = await BitcoinUtils.deploy();
    await bitcoinUtils.waitForDeployment();
    bitcoinUtilsAddress = await bitcoinUtils.getAddress();
    console.log("BitcoinUtils library deployed to:", bitcoinUtilsAddress);
  }

  // Deploy TrustlessBTC with linked library
  const TrustlessBTC = await ethers.getContractFactory("TrustlessBTC", {
    libraries: {
      BitcoinUtils: bitcoinUtilsAddress
    }
  });
  const tbtc = await TrustlessBTC.deploy(roflAppID, oracle);
  await tbtc.waitForDeployment();
  const tbtcAddress = await tbtc.getAddress();

  console.log("TrustlessBTC deployed to:", tbtcAddress);
  console.log("Bitcoin address:", await tbtc.bitcoinAddress());
  console.log("Public key:", await tbtc.publicKey());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 