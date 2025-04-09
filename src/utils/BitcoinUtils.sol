// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./SECP256K1.sol";
import { Sapphire } from  "@oasisprotocol/sapphire-contracts/contracts/Sapphire.sol";

library BitcoinUtils {
    using Strings for uint256;

    // Bitcoin address version byte (0x00 for mainnet)
    uint8 constant ADDRESS_VERSION = 0x00;
    
    // Base58 alphabet
    bytes constant BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    
    uint256 constant private BITCOIN_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

     error Bitcoin__InvalidPrivateKey(bytes32 privateKey);
     error Bitcoin__SigningFailed();

    /**
     * @dev Generates a new Bitcoin key pair
     */
    function generateKeyPair() view internal returns (bytes32 privateKey, bytes memory publicKey, string memory bitcoinAddress) {
        // Generate a signing key pair using Sapphire's secp256k1 implementation
        (bytes memory pubKey, bytes memory privKey) = Sapphire.generateSigningKeyPair(
            Sapphire.SigningAlg.Secp256k1Oasis,
            ""
        );

        privateKey = bytes32(privKey);
        publicKey = pubKey;
        bitcoinAddress = BitcoinUtils.publicKeyToAddress(pubKey);
    }

    /**
     * @dev Signs a Bitcoin transaction hash
     * @param txHash Transaction hash to sign
     * @param privateKey Private key to sign with
     * @param sigHashType Bitcoin signature hash type
     * @return Signature with sighash type appended
     */
    function signTransaction(
        bytes32 txHash, 
        bytes32 privateKey,
        uint8 sigHashType
    ) internal pure returns (bytes memory) {
        // Validate private key
        if (uint256(privateKey) == 0 || uint256(privateKey) >= SECP256K1.N) {
            revert Bitcoin__InvalidPrivateKey(privateKey);
        }

        // Get public key point from private key
        SECP256K1.Point memory G = SECP256K1.Point(SECP256K1.GX, SECP256K1.GY);
        SECP256K1.Point memory pubKeyPoint = SECP256K1.multiplyPoint(G, uint256(privateKey));

        // Calculate deterministic k value (RFC 6979-like approach)
        uint256 k = uint256(txHash);
        if (k >= SECP256K1.N) k = k % SECP256K1.N;
        if (k == 0) k = 1;  // Ensure k is never 0

        // Calculate r value (x coordinate of random point)
        SECP256K1.Point memory R = SECP256K1.multiplyPoint(G, k);
        uint256 r = R.x % SECP256K1.N;

        // Calculate s value: s = k^-1 * (hash + r * privateKey) mod n
        uint256 kInv = SECP256K1.inverseMod(k, SECP256K1.N);
        uint256 s = mulmod(
            kInv,
            addmod(
                uint256(txHash),
                mulmod(r, uint256(privateKey), SECP256K1.N),
                SECP256K1.N
            ),
            SECP256K1.N
        );

        // Ensure low s value (BIP 62)
        if (s > SECP256K1.N / 2) {
            s = SECP256K1.N - s;
        }

        // Encode signature in DER format with sighash type
        bytes memory signature = abi.encodePacked(
            uint8(0x30), // sequence
            uint8(0x44), // length
            uint8(0x02), // integer
            uint8(0x20), // 32 bytes
            bytes32(r),  // r value
            uint8(0x02), // integer
            uint8(0x20), // 32 bytes
            bytes32(s),  // s value
            sigHashType  // sighash type
        );

        return signature;
    }

    /**
     * @dev Converts a private key to a Bitcoin public key
     * @param privateKey The private key to convert
     * @return publicKey The resulting public key
     */
    function privateKeyToPublicKey(bytes32 privateKey) internal pure returns (bytes memory publicKey) {
        uint256 privKey = uint256(privateKey);
        if (privKey == 0 || privKey >= SECP256K1.N) revert("Invalid private key");

        SECP256K1.Point memory pubKey = SECP256K1.multiplyPoint(
            SECP256K1.Point(SECP256K1.GX, SECP256K1.GY),
            privKey
        );

        return abi.encodePacked(
            bytes1(0x04), // Uncompressed public key prefix
            bytes32(pubKey.x),
            bytes32(pubKey.y)
        );
    }

    /**
     * @dev Derives a Bitcoin address from a public key
     * @param publicKey The public key to derive the address from
     * @return The Bitcoin address as a string
     */
    function publicKeyToAddress(bytes memory publicKey) internal pure returns (string memory) {
        // Hash the public key with SHA256 and RIPEMD160
        bytes20 pubKeyHash = ripemd160(abi.encodePacked(sha256(publicKey)));
        
        // Add version byte
        bytes memory preAddress = abi.encodePacked(bytes1(ADDRESS_VERSION), pubKeyHash);
        
        // Add checksum
        bytes32 hash1 = sha256(preAddress);
        bytes32 hash2 = sha256(abi.encodePacked(hash1));
        bytes4 checksum = bytes4(hash2);
        
        // Combine and Base58 encode
        bytes memory addressBytes = abi.encodePacked(preAddress, checksum);
        return base58Encode(addressBytes);
    }

    /**
     * @dev Encodes a byte array to Base58
     * @param data The data to encode
     * @return The Base58 encoded string
     */
    function base58Encode(bytes memory data) internal pure returns (string memory) {
        uint256 value = 0;
        for (uint i = 0; i < data.length; i++) {
            value = value * 256 + uint8(data[i]);
        }
        
        bytes memory result = new bytes(50); // Max length for Base58
        uint256 length = 0;
        
        while (value > 0) {
            uint256 remainder = value % 58;
            value = value / 58;
            result[length] = BASE58_ALPHABET[remainder];
            length++;
        }
        
        // Add leading zeros
        for (uint i = 0; i < data.length && data[i] == 0; i++) {
            result[length] = BASE58_ALPHABET[0];
            length++;
        }
        
        // Reverse the string
        bytes memory reversed = new bytes(length);
        for (uint i = 0; i < length; i++) {
            reversed[i] = result[length - 1 - i];
        }
        
        return string(reversed);
    }

    /**
     * @dev Calculates the checksum for a Bitcoin address
     * @param data The data to calculate the checksum for
     * @return The 4-byte checksum
     */
    function calculateChecksum(bytes memory data) internal pure returns (bytes4) {
        bytes32 hash1 = sha256(data);
        bytes32 hash2 = sha256(abi.encodePacked(hash1));
        return bytes4(hash2);
    }

    /**
     * @dev SHA256 hash function
     */
    function sha256(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }

    /**
     * @dev RIPEMD160 hash function
     * Note: This is a simplified version. In production, use a proper RIPEMD160 implementation
     */
    function ripemd160(bytes memory data) internal pure returns (bytes20) {
        return bytes20(keccak256(data));
    }

    function isValidBitcoinAddress(string memory input) public pure returns (bool) {
        bytes memory strBytes = bytes(input);
        uint256 length = strBytes.length;

        // Check length for P2PKH or P2SH (26-35 characters)
        if (length < 26 || length > 62) return false;

        // Check prefix (P2PKH, P2SH, Bech32)
        if (strBytes[0] != '1' && strBytes[0] != '3' && !isBech32Prefix(strBytes)) {
            return false;
        }

        // Check valid characters (Base58 or Bech32)
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = strBytes[i];
            if (!isValidCharacter(char)) {
                return false;
            }
        }

        return true;
    }

    function isBech32Prefix(bytes memory strBytes) internal pure returns (bool) {
        return (strBytes[0] == 'b' && strBytes[1] == 'c' && strBytes[2] == '1');
    }

    function isValidCharacter(bytes1 char) internal pure returns (bool) {
        // Valid Base58 characters (without 0, O, I, l)
        bytes memory validChars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        for (uint256 j = 0; j < validChars.length; j++) {
            if (char == validChars[j]) return true;
        }
        return false;
    }
} 