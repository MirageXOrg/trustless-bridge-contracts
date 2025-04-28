import '@nomicfoundation/hardhat-chai-matchers';
import { expect } from "chai";
import { ethers } from "hardhat";

import { TrustlessBTC } from "../../typechain-types";

describe('TrustlessBTC', () => {
    let contract : TrustlessBTC;
    let owner: any;
    let oracle: any;
    let bob: any;

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
        const roflAppID = ethers.zeroPadValue("0x0102030405060708090a0b0c0d0e0f101112131415", 21);

        let tBtc = await ethers.getContractFactory("TrustlessBTC",  {
          libraries: {
            SECP256K1: secp256k1Address,
            RFC6979: rfc6979Address,
          },
        });
        contract = await tBtc.deploy(roflAppID, oracle.address);
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
        .to.be.revertedWith("Transaction hash already processed");
    });

    it('Burns tBTC', async () => {
        const burnId = 1;
        const txHash = "0x557dabfd2db86542a027a97779731c024e652b2a8ed5d01432541cb5ca7feba2";

        await expect(
            contract.connect(oracle).mint(bob.address, 1000, txHash)
        )

        await expect(
            contract.connect(bob).burn(1000, "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")   
        )
        .to.emit(contract, "Burn")
        .withArgs(burnId)
        .to.emit(contract, "BurnGenerateTransaction")
        .withArgs(burnId);

        await expect(contract.connect(oracle).signBurn(burnId, txHash))
        .to.emit(contract, "BurnSigned")
        .withArgs(burnId, txHash);

        await expect(contract.connect(oracle).validateBurnTransaction())
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