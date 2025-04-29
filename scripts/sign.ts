import { wrapEthersSigner } from '@oasisprotocol/sapphire-ethers-v6';
import { ethers, Wallet } from 'ethers';
import {SiweMessage} from 'siwe';
import fs from 'fs';

async function main() {

  // Load TrustlessBTC ABI
  const TRUSTLESS_BTC_ABI = JSON.parse(fs.readFileSync('artifacts/contracts/tBTC.sol/TrustlessBTC.json', 'utf8')).abi;
  const TRUSTLESS_BTC_ADDRESS = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0'; // TODO: Replace with actual deployed address
  const ETH_RPC_URL = 'http://127.0.0.1:8545'; // TODO: Replace with actual Ethereum RPC URL

  // Load TEST_HDWALLET mnemonic from env or use default
  const TEST_HDWALLET_MNEMONIC = process.env.TEST_HDWALLET || "test test test test test test test test test test test junk";
  const TEST_HDWALLET_PATH = "m/44'/60'/0'/0/0"; // Use first account by default

  // Set up ethers provider and contract
  const provider = new ethers.JsonRpcProvider(ETH_RPC_URL);
  const hdNode = ethers.HDNodeWallet.fromMnemonic(ethers.Mnemonic.fromPhrase(TEST_HDWALLET_MNEMONIC), TEST_HDWALLET_PATH);
  // const wallet = hdNode.connect(provider);
  const wallet = new Wallet('', provider); // fill with wallet
  const signer = wrapEthersSigner(wallet);

  console.log(wallet.address);
  const trustlessBtc = new ethers.Contract(TRUSTLESS_BTC_ADDRESS, TRUSTLESS_BTC_ABI, signer);
  const oracle = await trustlessBtc.oracle();
  console.log("Oracle:", oracle); 

  // Sign a message
  console.log("\nSigning message 'hello world'...");
  const message = "hello world";
  const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
  console.log("Message hash:", messageHash);

  try {
  //   const tx = await trustlessBtc.sign.staticCall(messageHash);
  //   const receipt = await tx.wait();
    
  //   // Parse and print RFC6979 events
  //   console.log("\nRFC6979 Debug Events:");
  //   for (const log of receipt.logs) {
  //     try {
  //       const parsedLog = rfc6979Interface.parseLog(log);
  //       if (parsedLog) {
  //         if (parsedLog.name === "KeccakInput") {
  //           console.log("\nInput:", parsedLog.args[0]);
  //         } else if (parsedLog.name === "KeccakOutput") {
  //           console.log("Output:", parsedLog.args[0]);
  //         }
  //       }
  //     } catch (e) {
  //       // Skip logs that aren't our events
  //       continue;
  //     }
  //   }

    const domain = await trustlessBtc.domain();
    console.log("domain: ", domain);
    console.log("oracle address:", wallet.address);

    const siweMsg = new SiweMessage({
        domain,
        address: wallet.address,
        statement: "Sign in with Ethereum to access the TrustlessBTC contract",
        uri: `http://${domain}`,
        version: "1",
        chainId: Number((await provider.getNetwork()).chainId)
    }).toMessage();
    console.log("SIWE Message:", siweMsg);

    const signature = await signer.signMessage(siweMsg);
    console.log("signature: ", signature);
    const sig = ethers.Signature.from(signature);
    console.log("sig: ", sig);
    const token = await trustlessBtc.login(siweMsg, sig);
    console.log("token: ", token);

    const [nonce, r, s, v] = await trustlessBtc.sign(messageHash, token);
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