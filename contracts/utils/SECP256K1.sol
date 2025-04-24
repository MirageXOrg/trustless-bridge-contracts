// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EllipticCurve.sol";

library SECP256K1 {
    uint256 public constant GX = 55066263022277343669578718895168534326250603453777594175500187360389116729240;
    uint256 public constant GY = 32670510020758816978083085130507043184471273380659243275938904335757337482424;
    uint256 public constant AA = 0;
    uint256 public constant PP = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    function derivePubKey(uint256 privKey) public pure returns (uint256 qx, uint256 qy) {
        (qx, qy) = EllipticCurve.ecMul(privKey, GX, GY, AA, PP);
    }

    function multiplyG(uint256 scalar) public pure returns (uint256 x, uint256 y) {
        return EllipticCurve.ecMul(scalar, GX, GY, AA, PP);
    }

    function inverseMod(uint256 x, uint256 n) public pure returns (uint256) {
        return EllipticCurve.invMod(x, n);
    }
}