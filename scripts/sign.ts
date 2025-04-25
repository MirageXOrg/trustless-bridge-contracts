import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Using account:", deployer.address);

  // Get the deployed TrustlessBTC contract
  const tbtcAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
  if (!tbtcAddress) {
    throw new Error("TRUSTLESS_BTC_ADDRESS environment variable not set");
  }

  const TrustlessBTC = await ethers.getContractFactory("TrustlessBTC", {
    libraries: {
      SECP256K1: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    },
  });
  const tbtc = TrustlessBTC.attach(tbtcAddress);

  // Get the RFC6979 interface
  const RFC6979 = await ethers.getContractFactory("RFC6979");
  const rfc6979Interface = RFC6979.interface;

  // Sign a message
  console.log("\nSigning message 'hello world'...");
  const message = "hello world";
  const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
  console.log("Message hash:", messageHash);

  try {
    const tx = await tbtc.sign(messageHash);
    const receipt = await tx.wait();
    
    // Parse and print RFC6979 events
    console.log("\nRFC6979 Debug Events:");
    for (const log of receipt.logs) {
      try {
        const parsedLog = rfc6979Interface.parseLog(log);
        if (parsedLog) {
          if (parsedLog.name === "KeccakInput") {
            console.log("\nInput:", parsedLog.args[0]);
          } else if (parsedLog.name === "KeccakOutput") {
            console.log("Output:", parsedLog.args[0]);
          }
        }
      } catch (e) {
        // Skip logs that aren't our events
        continue;
      }
    }

    const [nonce, r, s, v] = await tbtc.sign.staticCall(messageHash);
    console.log("\nSignature:");
    console.log("nonce:", "0x" + nonce.toString(16));
    console.log("r:", "0x" + r.toString(16));
    console.log("s:", "0x" + s.toString(16));
    console.log("v:", "0x" + v.toString(16));
  } catch (error) {
    console.error("Failed to sign message:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 