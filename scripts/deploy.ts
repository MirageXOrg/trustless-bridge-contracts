import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Get library addresses from env or deploy new ones
  let secp256k1Address = process.env.SECP256K1_ADDRESS;
  let rfc6979Address = process.env.RFC6979_ADDRESS;

  // Deploy SECP256K1 library if not provided
  if (!secp256k1Address) {
    console.log("SECP256K1 address not provided in env, deploying new library...");
    const SECP256K1 = await ethers.getContractFactory("SECP256K1");
    const secp256k1 = await SECP256K1.deploy();
    await secp256k1.waitForDeployment();
    secp256k1Address = await secp256k1.getAddress();
    console.log("SECP256K1 library deployed to:", secp256k1Address);
  } else {
    console.log("Using existing SECP256K1 library at:", secp256k1Address);
  }

  // Deploy RFC6979 library if not provided
  if (!rfc6979Address) {
    console.log("RFC6979 address not provided in env, deploying new library...");
    const RFC6979 = await ethers.getContractFactory("RFC6979");
    const rfc6979 = await RFC6979.deploy();
    await rfc6979.waitForDeployment();
    rfc6979Address = await rfc6979.getAddress();
    console.log("RFC6979 library deployed to:", rfc6979Address);
  } else {
    console.log("Using existing RFC6979 library at:", rfc6979Address);
  }

  // Create a bytes21 value (21 bytes = 42 hex characters)
  const roflAppID = ethers.zeroPadValue("0x0102030405060708090a0b0c0d0e0f101112131415", 21);
  const oracle = process.env.ORACLE_ADDRESS || "0x704bA7cA2B5e649cd0b77Fd0c2568cdb9C033048";

  // Deploy TrustlessBTC with linked libraries
  console.log("Deploying TrustlessBTC with linked SECP256K1 and RFC6979 libraries...");
  const TrustlessBTC = await ethers.getContractFactory("TrustlessBTC", {
    libraries: {
      SECP256K1: secp256k1Address,
      RFC6979: rfc6979Address,
    },
  });
  const tbtc = await TrustlessBTC.deploy(roflAppID, oracle, "trustless.btc");
  await tbtc.waitForDeployment();
  const tbtcAddress = await tbtc.getAddress();

  console.log("TrustlessBTC deployed to:", tbtcAddress);

  // Generate keys
  console.log("Generating Bitcoin keys...");
  try {
    const tx = await tbtc.generateKeys();
    await tx.wait();
    console.log("Keys generated successfully");
    console.log("Bitcoin address:", await tbtc.bitcoinAddress());
    console.log("Public key:", await tbtc.publicKey());
    // console.log("Private key:", await tbtc.privateKey());
  } catch (error) {
    console.error("Failed to generate keys:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 