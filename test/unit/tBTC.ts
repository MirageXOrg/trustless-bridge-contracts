import { expect } from "chai";
import { ethers } from "hardhat";

import { TrustlessBTC } from "../../typechain-types";

describe('TrustlessBTC', () => {
    let contract : TrustlessBTC;

    before(async () => {
        const oracle = (await ethers.getSigners())[1];

        const SECP256K1 = await ethers.getContractFactory("SECP256K1");
        const secp256k1 = await SECP256K1.deploy();
        await secp256k1.waitForDeployment();
        const secp256k1Address = await secp256k1.getAddress();
      
      
        const RFC6979 = await ethers.getContractFactory("RFC6979");
        const rfc6979 = await RFC6979.deploy();
        await rfc6979.waitForDeployment();
        const rfc6979Address = await rfc6979.getAddress();
      
        // Create a bytes21 value (21 bytes = 42 hex characters)
        const roflAppID = ethers.zeroPadValue("0x0102030405060708090a0b0c0d0e0f101112131415", 21);

        let tBtc = await ethers.getContractFactory("TrustlessBTC",  {
          libraries: {
            SECP256K1: secp256k1Address,
            RFC6979: rfc6979Address,
          },
        });
        contract = await tBtc.deploy(roflAppID, oracle.address);
        await contract.waitForDeployment();
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

        await expect(
            contract.submitMintTransactionProof(txHash, signature, ethAddress)
        ).to.be.revertedWith("Transaction hash already submitted");
    });
});
