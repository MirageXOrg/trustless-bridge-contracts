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

        bytes memory randomnes = Sapphire.randomBytes(32, "");

         (, bytes memory sk) = Sapphire.generateSigningKeyPair(
            Sapphire.SigningAlg.Secp256k1PrehashedSha256,
            randomnes
        );

        return bytes32(sk);
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
     * @dev Signs a message using Sapphire
     * @param privateKey The private key
     * @param msgHash The message hash to sign
     */
     function sign(
        bytes32 privateKey,
        bytes32 msgHash
    ) internal view returns (bytes memory signature) {

        signature = Sapphire.sign(
            Sapphire.SigningAlg.Secp256k1PrehashedSha256,
            bytes.concat(privateKey),
            bytes.concat(msgHash),
            ""
        );
    }

    /**
     * @dev Verifies a signature
     * @param publicKey The public key to verify against
     * @param msgHash The message hash that was signed
     * @param signature The signature to verify
     * @return True if the signature is valid, false otherwise
     */
    function verify(
        bytes memory publicKey,
        bytes32 msgHash,
        bytes memory signature
    ) internal view returns (bool) {
        return Sapphire.verify(
            Sapphire.SigningAlg.Secp256k1PrehashedSha256,
            publicKey,
            bytes.concat(msgHash),
            "",
            signature
        );
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
                break; // Use the first '1' as separator
            }
        }
        if (separatorIndex == -1 || separatorIndex < 1 || separatorIndex + 7 > int256(addr.length)) {
            return false; // separator not found or too late
        }

        // HRP check
        if (!(addr[0] == 'b' && addr[1] == 'c') && !(addr[0] == 't' && addr[1] == 'b')) {
            return false;
        }

        // Extract HRP (human-readable part)
        bytes memory hrp = new bytes(uint256(separatorIndex));
        for (uint256 i = 0; i < uint256(separatorIndex); i++) {
            hrp[i] = addr[i];
        }

        // Check valid Bech32 charset after separator and convert to 5-bit values
        bytes memory charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
        uint8[] memory data = new uint8[](addr.length - uint256(separatorIndex) - 1);
        for (uint256 i = uint256(separatorIndex + 1); i < addr.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < charset.length; j++) {
                if (addr[i] == charset[j]) {
                    data[i - uint256(separatorIndex) - 1] = uint8(j);
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        // Verify checksum
        return verifyBech32Checksum(hrp, data);
    }

    /**
     * @dev Verifies the checksum of a Bech32 address
     * @param hrp The human-readable part
     * @param data The data part (5-bit values)
     * @return true if the checksum is valid, false otherwise
     */
    function verifyBech32Checksum(bytes memory hrp, uint8[] memory data) private pure returns (bool) {
        // Try both Bech32 and Bech32m formats
        return verifyChecksum(hrp, data, 1) || verifyChecksum(hrp, data, 0x2bc830a3);
    }

    /**
     * @dev Verifies the checksum with a specific constant
     * @param hrp The human-readable part
     * @param data The data part (5-bit values)
     * @param constnt The checksum constant (1 for Bech32, 0x2bc830a3 for Bech32m)
     * @return true if the checksum is valid, false otherwise
     */
    function verifyChecksum(bytes memory hrp, uint8[] memory data, uint32 checksumConstant) private pure returns (bool) {
        uint32 chk = 1;
        uint32 value;

        // Process HRP characters
        for (uint256 i = 0; i < hrp.length; i++) {
            value = uint32(uint8(hrp[i]) >> 5);
            chk = bech32Polymod(chk) ^ value;
        }

        chk = bech32Polymod(chk);

        for (uint256 i = 0; i < hrp.length; i++) {
            value = uint32(uint8(hrp[i]) & 0x1f);
            chk = bech32Polymod(chk) ^ value;
        }

        // Process data characters
        for (uint256 i = 0; i < data.length - 6; i++) {
            chk = bech32Polymod(chk) ^ uint32(data[i]);
        }

        // Process checksum characters
        for (uint256 i = 0; i < 6; i++) {
            chk = bech32Polymod(chk);
        }

        // Final checksum
        chk ^= checksumConstant;

        // Verify checksum
        for (uint256 i = 0; i < 6; i++) {
            if (uint32(data[data.length - 6 + i]) != ((chk >> (5 * (5 - i))) & 0x1f)) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Bech32 polymod function for checksum calculation
     * @param pre The previous value
     * @return The next value
     */
    function bech32Polymod(uint32 pre) private pure returns (uint32) {
        uint8[5] memory generator = [0x3b, 0x1e, 0x03, 0x2a, 0x22]; // Generator coefficients
        uint32 b = pre >> 25;
        uint32 ret = ((pre & 0x1ffffff) << 5);

        for (uint256 i = 0; i < 5; i++) {
            if (((b >> i) & 1) == 1) {
                ret ^= uint32(generator[i]) << 25;
            }
        }

        return ret;
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
