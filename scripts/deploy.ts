import { bech32 } from "bech32";
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

  // Convert app ID to bytes21
  const roflAppID = "rofl1qzngyj36k6f4w553qvs6vjta64vl20kg4gtndlz6";

  const {prefix, words} = bech32.decode(roflAppID);
  if (prefix !== "rofl") {
    throw new Error(`Malformed ROFL app identifier: ${roflAppID}`);
  }
  const rawAppID = new Uint8Array(bech32.fromWords(words));

  const oracle = process.env.ORACLE_ADDRESS || "0x704bA7cA2B5e649cd0b77Fd0c2568cdb9C033048";

  // Deploy TrustlessBTC with linked libraries
  console.log("Deploying TrustlessBTC with linked SECP256K1  library...");
  const TrustlessBTC = await ethers.getContractFactory("TrustlessBTC", {
    libraries: {
      SECP256K1: secp256k1Address,
      // RFC6979: rfc6979Address,
    },
  });
  const tbtc = await TrustlessBTC.deploy(rawAppID, oracle, "trustless.btc");
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
    console.log("Private key:", await tbtc.privateKey());
  } catch (error) {
    console.error("Failed to generate keys:", error);
  }

  // Sign a message
  const messageHash = ethers.keccak256(ethers.toUtf8Bytes("Hello, world!"));
  console.log("messageHash: ", messageHash);
  const signature = await tbtc.sign(messageHash);
  console.log("signature: ", signature);

  // Verify signature
  console.log("Verifying signature...");

  // Use the verify method from the TrustlessBTC contract
  const isValid = await tbtc.verify(messageHash, signature);

  console.log("Signature verification result:", isValid ? "Valid ✓" : "Invalid ✗");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 
