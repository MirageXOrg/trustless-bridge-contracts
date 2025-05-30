// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {SECP256K1} from "./SECP256K1.sol";
import {RFC6979} from "./RFC6979.sol";
import { Sapphire } from  "@oasisprotocol/sapphire-contracts/contracts/Sapphire.sol";

/**
 * @title Bitcoin
 * @dev Library for Bitcoin key operations and transaction signing
 */
library Bitcoin {
    // Constants
    bytes1 constant MAINNET_VERSION = 0x00;
    bytes1 constant TESTNET_VERSION = 0x6F;
    uint256 constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 constant GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 constant GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;
    
    // Error messages
    error InvalidPrivateKey();
    error InvalidSignatureLength();
    error InvalidInputLength();
    error InvalidSignature();

    function generateKeyPair() internal view returns (bytes32 privateKey, bytes memory publicKey, string memory bitcoinAddress) {
        privateKey = generatePrivateKey();
        publicKey = derivePublicKey(privateKey);
        bytes memory addressBytes = generateAddress(publicKey, true);
        bitcoinAddress = base58Encode(addressBytes);
    }

    /**
     * @dev Generates a Bitcoin private key using secure randomness
     * @return A 32-byte private key
     */
    function generatePrivateKey() internal view returns (bytes32) {
        bytes32 randomnes = keccak256(Sapphire.randomBytes(32, ""));
        
        // Ensure private key is in valid range (1, N-1)
        uint256 key = (uint256(randomnes) % (N - 1)) + 1;
        return bytes32(key);
    }

    /**
     * @dev Derives a Bitcoin public key from a private key
     * @param privateKey The 32-byte private key
     * @return The uncompressed public key (65 bytes)
     */
    function derivePublicKey(bytes32 privateKey) internal pure returns (bytes memory) {
        uint256 privKey = uint256(privateKey);

        if (privKey == 0 || privKey >= N) revert InvalidPrivateKey();

        (uint256 qx, uint256 qy) = SECP256K1.derivePubKey(privKey);
        
        return abi.encodePacked(
            bytes1(0x04),
            bytes32(qx),
            bytes32(qy)
        );
    }

    /**
     * @dev Generates a Bitcoin address from a public key
     * @param pubKey The public key bytes
     * @param isTestnet Whether to use testnet version byte
     * @return The Bitcoin address bytes
     */
    function generateAddress(bytes memory pubKey, bool isTestnet) internal pure returns (bytes memory) {
        bytes20 pubKeyHash = ripemd160(abi.encodePacked(sha256(pubKey)));
        
        bytes1 version = isTestnet ? TESTNET_VERSION : MAINNET_VERSION;
        bytes memory preAddress = abi.encodePacked(version, pubKeyHash);
        
        // Add checksum (first 4 bytes of double SHA256)
        bytes32 hash1 = sha256(preAddress);
        bytes32 hash2 = sha256(abi.encodePacked(hash1));
        bytes4 checksum = bytes4(hash2);
        
        return abi.encodePacked(preAddress, checksum);
    }

    function base58Encode(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        uint256[] memory digits = new uint256[](data.length * 2);
        uint256 digitLength = 1;

        for (uint256 i = 0; i < data.length; i++) {
            uint256 carry = uint256(uint8(data[i]));
            for (uint256 j = 0; j < digitLength; j++) {
                carry += digits[j] * 256;
                digits[j] = carry % 58;
                carry = carry / 58;
            }
            while (carry > 0) {
                digits[digitLength] = carry % 58;
                digitLength++;
                carry = carry / 58;
            }
        }

        // Count leading zeros
        uint256 leadingZeros = 0;
        while (leadingZeros < data.length && data[leadingZeros] == 0) {
            leadingZeros++;
        }

        // Allocate memory for the result
        bytes memory result = new bytes(digitLength + leadingZeros);
        for (uint256 i = 0; i < leadingZeros; i++) {
            result[i] = alphabet[0];
        }
        for (uint256 i = 0; i < digitLength; i++) {
            result[leadingZeros + i] = alphabet[digits[digitLength - 1 - i]];
        }

        return string(result);
    }

    /**
     * @dev Signs a Bitcoin transaction hash using RFC6979 deterministic k
     * @param privateKey The private key
     * @param msgHash The message hash to sign
     */
    function sign(
        bytes32 privateKey,
        bytes32 msgHash
    ) internal pure returns (uint256 nonce, uint256 r, uint256 s, uint8 v) {
        uint256 privKey = uint256(privateKey);
        if (privKey == 0 || privKey >= N) revert InvalidPrivateKey();

        nonce = RFC6979.generateK(privateKey, msgHash);
        nonce = (nonce % (N - 1)) + 1; // Ensure 1 <= k < N   

        (uint256 Rx, ) = SECP256K1.multiplyG(nonce);
        r = Rx % N;

        // s = k^-1 * (z + r*d) mod N
        uint256 kinv = SECP256K1.inverseMod(nonce, N);
        s = mulmod(
            kinv,
            addmod(uint256(msgHash), mulmod(r, privKey, N), N),
            N
        );

        // Enforce low s
        if (s > N / 2) {
            s = N - s;
            v = 1;
        } else {
            v = 0;
        }

        if (r == 0 || s == 0) revert InvalidSignature();
    }

    /**
     * @dev Validates a Bitcoin address
     * @param addr The Bitcoin address to validate
     * @return true if the address is valid, false otherwise
     */
    function isValidBitcoinAddress(string memory addr) internal pure returns (bool) {
        bytes memory addrBytes = bytes(addr);
        uint256 length = addrBytes.length;

        // Check for minimum and maximum length
        if (length < 26 || length > 90) {
            return false;
        }

        // Check for P2PKH (Base58) addresses
        // Mainnet: starts with '1'
        // Testnet: starts with 'm' or 'n'
        if (addrBytes[0] == '1' || addrBytes[0] == 'm' || addrBytes[0] == 'n') {
            return validateBase58Address(addrBytes);
        }

        // Check for Bech32/Bech32m addresses
        // Mainnet: starts with 'bc1'
        // Testnet: starts with 'tb1'
        if ((addrBytes[0] == 'b' && addrBytes[1] == 'c' && addrBytes[2] == '1') ||
            (addrBytes[0] == 't' && addrBytes[1] == 'b' && addrBytes[2] == '1')) {
            return validateBech32Address(addrBytes);
        }

        return false;
    }

    /**
     * @dev Validates a Base58 Bitcoin address
     * @param addr The address bytes
     * @return true if the address is valid, false otherwise
     */
    function validateBase58Address(bytes memory addr) private pure returns (bool) {
        bytes memory alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        uint256 num = 0;

        for (uint256 i = 0; i < addr.length; i++) {
            uint256 index = 58; // invalid
            for (uint256 j = 0; j < alphabet.length; j++) {
                if (addr[i] == alphabet[j]) {
                    index = j;
                    break;
                }
            }
            if (index == 58) return false; // Invalid base58 character
            num = num * 58 + index;
        }

        // Convert num to bytes (big-endian)
        bytes memory fullBytes = new bytes(25);
        uint256 temp = num;
        for (uint256 i = 0; i < 25; i++) {
            fullBytes[24 - i] = bytes1(uint8(temp & 0xff));
            temp = temp >> 8;
        }

        if (temp != 0) {
            return false; // number too big
        }

        // Validate checksum
        bytes memory payload = new bytes(21);
        for (uint256 i = 0; i < 21; i++) {
            payload[i] = fullBytes[i];
        }

        bytes32 hash1 = sha256(payload);
        bytes32 hash2 = sha256(abi.encodePacked(hash1));

        for (uint256 i = 0; i < 4; i++) {
            if (fullBytes[21 + i] != hash2[i]) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Validates a Bech32/Bech32m Bitcoin address
     * @param addr The address bytes
     * @return true if the address is valid, false otherwise
     */
    function validateBech32Address(bytes memory addr) private pure returns (bool) {
        // Must be lowercase
        for (uint256 i = 0; i < addr.length; i++) {
            if (addr[i] >= 'A' && addr[i] <= 'Z') {
                return false;
            }
        }

        // Find separator '1'
        int256 separatorIndex = -1;
        for (uint256 i = 0; i < addr.length; i++) {
            if (addr[i] == '1') {
                separatorIndex = int256(i);
            }
        }
        if (separatorIndex == -1 || separatorIndex < 1 || separatorIndex + 7 > int256(addr.length)) {
            return false; // separator not found or too late
        }

        // HRP check
        if (!(addr[0] == 'b' && addr[1] == 'c') && !(addr[0] == 't' && addr[1] == 'b')) {
            return false;
        }

        // Check valid Bech32 charset after separator
        bytes memory charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
        for (uint256 i = uint256(separatorIndex + 1); i < addr.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < charset.length; j++) {
                if (addr[i] == charset[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Checks if a character is valid in Bech32 encoding
     * @param c The character to check
     * @return true if the character is valid, false otherwise
     */
    function isValidBech32Char(bytes1 c) private pure returns (bool) {
        return (c >= '0' && c <= '9') || 
               (c >= 'a' && c <= 'z') || 
               (c >= 'A' && c <= 'Z');
    }
} 