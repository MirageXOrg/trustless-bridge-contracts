import '@nomicfoundation/hardhat-chai-matchers';
import { expect } from "chai";
import { ethers } from "hardhat";
import {SiweMessage} from 'siwe';

import { TrustlessBTC } from "../../typechain-types";

describe('TrustlessBTC', () => {
    let contract : TrustlessBTC;
    let owner: any;
    let oracle: any;
    let bob: any;
    let roflAppID: any;

    before(async () => {
        [owner, oracle, bob] = (await ethers.getSigners());

        const SECP256K1 = await ethers.getContractFactory("SECP256K1");
        const secp256k1 = await SECP256K1.deploy();
        await secp256k1.waitForDeployment();
        const secp256k1Address = await secp256k1.getAddress();
      
      
        const RFC6979 = await ethers.getContractFactory("RFC6979");
        const rfc6979 = await RFC6979.deploy();
        await rfc6979.waitForDeployment();
        const rfc6979Address = await rfc6979.getAddress();
      
        // Create a bytes21 value (21 bytes = 42 hex characters)
        roflAppID = ethers.zeroPadValue("0x0102030405060708090a0b0c0d0e0f101112131415", 21);

        let tBtc = await ethers.getContractFactory("TrustlessBTC",  {
          libraries: {
            SECP256K1: secp256k1Address,
            RFC6979: rfc6979Address,
          },
        });
        contract = await tBtc.deploy(roflAppID, oracle.address, "localhost");
        await contract.waitForDeployment();
        await contract.generateKeys();
    });

    it('Submits a transaction proof', async () => {
        const txHash = "0x557dabfd2db86542a027a97779731c024e652b2a8ed5d01432541cb5ca7feba2";
        const signature = "IH/+UDuwAiQ52OFss5ju7EdsVw30LXXr4YrZT29JL/oaUVlMf1Rho7lqUyuilabDJQmXo+3kDLw4FIrsEezY+wU=";
        const ethAddress = "0x96Ac3ed608b69cB86ed4A8E960DBDB9910199347";

        await expect(
            contract.submitMintTransactionProof(txHash, signature, ethAddress)
        )
        .to.emit(contract, "TransactionProofSubmitted")
        .withArgs(txHash, signature, ethAddress);
    });

    it('Signs a message via oracle', async () => {
        const messageHash = "0x557dabfd2db86542a027a97779731c024e652b2a8ed5d01432541cb5ca7feba2";
        const [nonce, r, s, v] = await contract.connect(oracle).sign(messageHash, "0x");
        expect(r).to.not.be.undefined;
        expect(s).to.not.be.undefined;
        expect(v).to.not.be.undefined;
    });

    it.skip('Signs a message via siwe auth', async () => {
        const messageHash = "0x557dabfd2db86542a027a97779731c024e652b2a8ed5d01432541cb5ca7feba2";
        console.log("domain: ", await contract.domain());
        console.log("oracle address:", oracle.address);

        const siweMsg = new SiweMessage({
            domain: await contract.domain(),
            address: oracle.address,
            statement: "Sign in with Ethereum to access the TrustlessBTC contract",
            uri: "http://localhost:3000",
            version: "1",
            chainId: Number((await ethers.provider.getNetwork()).chainId)
        }).toMessage();
        console.log("SIWE Message:", siweMsg);

        const signature = await oracle.signMessage(siweMsg);
        console.log("signature: ", signature);
        const sig = ethers.Signature.from(signature);
        console.log("sig: ", sig);
        const token = await contract.login(siweMsg, sig);
        console.log("token: ", token);
        const [nonce, r, s, v] = await contract.sign(messageHash, token);
        console.log(nonce, r, s, v);
        expect(r).to.not.be.undefined;
        expect(s).to.not.be.undefined;
        expect(v).to.not.be.undefined;
    });

    it('Mints tBTC', async () => {
        const txHash = "0x557dabfd2db86542a027a97779731c024e652b2a8ed5d01432541cb5ca7feba2";

        await expect(
            contract.connect(owner).mint(bob.address, 1000, txHash)
        )
        .to.be.revertedWithCustomError(contract, "UnauthorizedOracle");

        await expect(
            contract.connect(oracle).mint(bob.address, 1000, txHash)
        )
        .to.emit(contract, "Transfer")
        .withArgs("0x0000000000000000000000000000000000000000", bob.address, 1000);

        await expect(
            contract.connect(oracle).mint(bob.address, 1000, txHash)
        )
        .to.be.revertedWithCustomError(contract, "TransactionAlreadyProcessed");
    });

    it('Burns tBTC', async () => {
        const burnId = 1;
        const txHash = "0x557dabfd2db86542a027a97779731c024e652b2a8ed5d01432541cb5ca7feba2";
        const rawTxHex = "01000000016dbddb085b1d8af75184f0bc01fad58d1266e9b63c5088155c5e4fc4e558a376000000008b483045022100884d142d86652a3f47ba4746ec719bbfbd040a570b1deccbb6498c75c4ae24cb02204b9f039ff08df09cbe9f6addac960298cad530a863ea8f53982c09db8f6e381301410484ecc0d46f1918b30928fa0e4ed99f16a0fb4fde0735e7ade8416ab9fe423cc5412336376789d172787ec3457eee41c04f4938de5cc17b4a10fa336a8d752adffffffff0240420f00000000001976a91462e907b15cbf27d5425399ebf6f0fb50ebb88f1888ac40420f00000000001976a91462e907b15cbf27d5425399ebf6f0fb50ebb88f1888ac00000000"
        const rawTx = ethers.toUtf8Bytes(rawTxHex);

        await expect(
            contract.connect(oracle).mint(bob.address, 1000, txHash)
        )

        await expect(
            contract.connect(bob).burn(1000, "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")   
        )
        .to.emit(contract, "Transfer")
        .withArgs(bob.address, "0x0000000000000000000000000000000000000000", 1000)
        .to.emit(contract, "BurnGenerateTransaction")
        .withArgs(burnId);

        await expect(contract.connect(oracle).signBurn(burnId, rawTx, txHash))
        .to.emit(contract, "BurnSigned")
        .withArgs(burnId, rawTx);

        await expect(contract.connect(oracle).requestValidateBurnBitcoinTransaction())
        .to.emit(contract, "BurnValidateTransaction")
        .withArgs(burnId);

        await expect(contract.connect(oracle).validateBurn(burnId))
        .to.emit(contract, "BurnValidated")
        .withArgs(burnId);
    }); 
});



// await expect(
//     contract.submitMintTransactionProof(txHash, signature, ethAddress)
// ).to.be.revertedWith("Transaction hash already submitted");