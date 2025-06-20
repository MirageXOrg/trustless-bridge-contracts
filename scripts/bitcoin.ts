import axios from 'axios';
import * as bitcoin from 'bitcoinjs-lib';
import BN from 'bn.js';
import * as bip66 from 'bip66';
import { ethers } from 'ethers';
import fs from 'fs';
import * as dotenv from 'dotenv';
dotenv.config();


function encodeDerSignature(r: BN, s: BN): Buffer {
    const rBuf = toPositiveBuffer(r.toArrayLike(Buffer, 'be'));
    const sBuf = toPositiveBuffer(s.toArrayLike(Buffer, 'be'));
    return Buffer.from(bip66.encode(rBuf, sBuf));
}

function toPositiveBuffer(buf: Buffer): Buffer {
    if (buf[0] & 0x80) {
        // Prepend 0x00 if the highest bit is set
        return Buffer.concat([Buffer.from([0x00]), buf]);
    }
    return buf;
}

// Calculate transaction amounts
function calculateAmounts(
    utxoAmountSat: number,
    amountToSendSat: number,
    feeRateSatPerByte: number = 1,
    estimatedTxSizeBytes: number = 250
): { amountToSendSat: number; change: number; fee: number } {
    const fee = feeRateSatPerByte * estimatedTxSizeBytes;
    const change = utxoAmountSat - amountToSendSat - fee;
    if (change < 0) {
        throw new Error("Not enough funds to cover destination + fee.");
    }
    return { amountToSendSat, change, fee };
}

// Get all UTXOs for an address
async function getAllUtxos(address: string): Promise<any[]> {
    const url = `https://blockstream.info/testnet/api/address/${address}/utxo`;
    const response = await axios.get(url);
    if (!response.data || response.data.length === 0) {
        throw new Error("No UTXOs available");
    }
    return response.data;
}

// Helper to fetch raw transaction hex for a given txid
async function fetchRawTx(txid: string): Promise<string> {
    const url = `https://blockstream.info/testnet/api/tx/${txid}/hex`;
    const response = await axios.get(url);
    return response.data;
}

// Load TrustlessBTC ABI
const TRUSTLESS_BTC_ABI = JSON.parse(fs.readFileSync('artifacts/contracts/tBTC.sol/TrustlessBTC.json', 'utf8')).abi;
const TRUSTLESS_BTC_ADDRESS = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512'; // TODO: Replace with actual deployed address
const ETH_RPC_URL = 'http://127.0.0.1:8545'; // TODO: Replace with actual Ethereum RPC URL

// Load TEST_HDWALLET mnemonic from env or use default
const TEST_HDWALLET_MNEMONIC = process.env.TEST_HDWALLET || "test test test test test test test test test test test junk";
const TEST_HDWALLET_PATH = "m/44'/60'/0'/0/0"; // Use first account by default

// Send custom signed transaction using TrustlessBTC contract for signing
async function sendCustomSignedTransaction(
    utxos: any[],
    destinationAddress: string,
    destinationAmountSat: number,
    changeAddress: string,
    changeAmountSat: number,
    btcNetworkRpcUrl: string
): Promise<any> {
    const network = bitcoin.networks.testnet;
    const psbt = new bitcoin.Psbt({ network });

    // Set up ethers provider and contract
    const provider = new ethers.JsonRpcProvider(ETH_RPC_URL);
    const hdNode = ethers.HDNodeWallet.fromMnemonic(ethers.Mnemonic.fromPhrase(TEST_HDWALLET_MNEMONIC), TEST_HDWALLET_PATH);
    const wallet = hdNode.connect(provider);
    const trustlessBtc = new ethers.Contract(TRUSTLESS_BTC_ADDRESS, TRUSTLESS_BTC_ABI, wallet);

    // Add inputs (fetch raw tx for each UTXO)
    for (const utxo of utxos) {
        const rawTxHex = await fetchRawTx(utxo.txid);
        psbt.addInput({
            hash: utxo.txid,
            index: utxo.vout,
            nonWitnessUtxo: Buffer.from(rawTxHex, 'hex'),
        });
    }

    // Add outputs
    psbt.addOutput({
        address: destinationAddress,
        value: destinationAmountSat,
    });
    psbt.addOutput({
        address: changeAddress,
        value: changeAmountSat,
    });

    // Get public key from contract (cache for all inputs)
    const pubKeyHex = await trustlessBtc.publicKey();
    // pubKeyHex is likely a hex string (e.g., '0x04...'), so convert to Buffer
    const pubKeyBuffer = Buffer.from(pubKeyHex.startsWith('0x') ? pubKeyHex.slice(2) : pubKeyHex, 'hex');

    // Custom sign each input using TrustlessBTC contract
    for (let i = 0; i < utxos.length; i++) {
        const tx = (psbt as any).__CACHE.__TX;
        const sighashType = bitcoin.Transaction.SIGHASH_ALL;
        // Use the correct script for the UTXO being spent (P2PKH)
        const utxoScript = bitcoin.address.toOutputScript(changeAddress, network);
        const sighash = tx.hashForSignature(i, utxoScript, sighashType);

        // Call TrustlessBTC contract to sign the sighash
        const sighashHex = '0x' + sighash.toString('hex');
        const { signature } = await trustlessBtc.sign.staticCall(sighashHex);
        // const { nonce, r, s, v } = await trustlessBtc.sign.staticCall(sighashHex);

        console.log("signature", signature);
        // console.log("r", r);
        // console.log("s", s);
        // console.log("v", v);

        // Convert r, s to Buffer
        // let rBuf = Buffer.from(r.toString(16).padStart(64, '0'), 'hex');
        // let sBuf = Buffer.from(s.toString(16).padStart(64, '0'), 'hex');
        // rBuf = toPositiveBuffer(rBuf);
        // sBuf = toPositiveBuffer(sBuf);
        // let derSig = Buffer.concat([
        //     encodeDerSignature(new BN(rBuf), new BN(sBuf)),
        //     Buffer.from([sighashType])
        // ]);
        psbt.updateInput(i, {
            partialSig: [{
                pubkey: pubKeyBuffer,
                signature
            }]
        });
        psbt.finalizeInput(i);
    }

    const rawTxHex = psbt.extractTransaction().toHex();

    // Send transaction
    const response = await axios.post(btcNetworkRpcUrl, {
        jsonrpc: "1.0",
        id: "sendtx",
        method: "sendrawtransaction",
        params: [rawTxHex],
    });
    return response.data;
}

// Main execution
async function main() {
    // === Get address from contract ===
    const provider = new ethers.JsonRpcProvider(ETH_RPC_URL);
    const trustlessBtc = new ethers.Contract(TRUSTLESS_BTC_ADDRESS, TRUSTLESS_BTC_ABI, provider);
    const address = await trustlessBtc.bitcoinAddress();
    console.log("Address:", address);

    // === Get UTXOs and Calculate ===
    const utxos = await getAllUtxos(address);
    const totalBalance = utxos.reduce((sum, utxo) => sum + utxo.value, 0);
    console.log(`Total balance: ${totalBalance} satoshis`);
    console.log("UTXOs:", utxos);

    const destinationAmountSat = 1000; // 0.00001 BTC
    const estimatedTxSizeBytes = 254 * utxos.length;
    const { amountToSendSat, change, fee } = calculateAmounts(
        totalBalance,
        destinationAmountSat,
        1,
        estimatedTxSizeBytes
    );

    // === Send transaction ===
    const txResult = await sendCustomSignedTransaction(
        utxos,
        "tb1qv0jerhgyxpa7n48qghsuufwrmxh5xt969m9475",
        amountToSendSat,
        address,
        change,
        "https://bitcoin-testnet-rpc.publicnode.com/"
    );

    console.log("Transaction result:", txResult);
}

main().catch(console.error);
