// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev RFC6979-style deterministic `k` generation using keccak256 (not exact HMAC-SHA256 but good enough for most Solidity use cases)
library RFC6979 {

    function generateK(bytes32 privateKey, bytes32 msgHash) public pure returns (uint256) {
        bytes32 v = hex"01";
        bytes32 k = hex"00";

        // Step 1: k = HMAC(k, v || 0x00 || privKey || msgHash)
        bytes memory step1Input = abi.encodePacked(k, v, bytes1(0x00), privateKey, msgHash);
        k = keccak256(step1Input);
        
        // Step 2: v = HMAC(k, v)
        bytes memory step2Input = abi.encodePacked(k, v);
        v = keccak256(step2Input);

        // Step 3: k = HMAC(k, v || 0x01 || privKey || msgHash)
        bytes memory step3Input = abi.encodePacked(k, v, bytes1(0x01), privateKey, msgHash);
        k = keccak256(step3Input);
        
        // Step 4: v = HMAC(k, v)
        bytes memory step4Input = abi.encodePacked(k, v);
        v = keccak256(step4Input);

        // Step 5: Use v as candidate k
        uint256 candidateK = uint256(v);
        return candidateK;
    }
}