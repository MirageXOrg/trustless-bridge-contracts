// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title SECP256K1
 * @dev Library for operations on the secp256k1 curve used by Bitcoin
 */
library SECP256K1 {
    // Curve parameters
    uint256 constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 constant GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 constant GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;
    uint256 constant A = 0;  // Curve coefficient A
    uint256 constant B = 7;  // Curve coefficient B

    // Error messages
    error InvalidPoint();
    error InvalidScalar();

    struct Point {
        uint256 x;
        uint256 y;
    }

    /**
     * @dev Checks if point is on curve y^2 = x^3 + 7
     */
    function isOnCurve(Point memory point) internal pure returns (bool) {
        if (point.x >= P || point.y >= P) {
            return false;
        }
        
        uint256 left = mulmod(point.y, point.y, P);
        uint256 right = addmod(
            mulmod(
                mulmod(point.x, point.x, P),
                point.x,
                P
            ),
            B,
            P
        );
        
        return left == right;
    }

    /**
     * @dev Adds two points on the curve
     */
    function addPoints(Point memory p1, Point memory p2) internal pure returns (Point memory) {
        if (!isOnCurve(p1) || !isOnCurve(p2)) revert InvalidPoint();

        uint256 lambda;
        if (p1.x == p2.x) {
            if (p1.y != p2.y) {
                // Return point at infinity
                return Point(0, 0);
            }
            // Point doubling
            lambda = mulmod(
                addmod(
                    mulmod(3, mulmod(p1.x, p1.x, P), P),
                    A,
                    P
                ),
                inverseMod(mulmod(2, p1.y, P), P),
                P
            );
        } else {
            // Point addition
            lambda = mulmod(
                addmod(p2.y, P - p1.y, P),
                inverseMod(addmod(p2.x, P - p1.x, P), P),
                P
            );
        }

        uint256 x3 = addmod(
            mulmod(lambda, lambda, P),
            P - addmod(p1.x, p2.x, P),
            P
        );
        
        return Point(
            x3,
            addmod(
                mulmod(lambda, addmod(p1.x, P - x3, P), P),
                P - p1.y,
                P
            )
        );
    }

    /**
     * @dev Multiplies a point by a scalar
     */
    function multiplyPoint(Point memory p, uint256 scalar) internal pure returns (Point memory) {
        if (!isOnCurve(p)) revert InvalidPoint();
        if (scalar >= N) revert InvalidScalar();
        if (scalar == 0) return Point(0, 0);

        Point memory result = Point(0, 0);
        Point memory current = p;

        for (uint256 i = 0; scalar != 0; i++) {
            if (scalar & 1 == 1) {
                if (result.x == 0 && result.y == 0) {
                    result = current;
                } else {
                    result = addPoints(result, current);
                }
            }
            current = addPoints(current, current);
            scalar = scalar >> 1;
        }

        return result;
    }

    /**
     * @dev Computes modular multiplicative inverse using Extended Euclidean Algorithm
     */
    function inverseMod(uint256 a, uint256 n) internal pure returns (uint256) {
        if (a == 0 || n == 0) revert InvalidScalar();
        
        int256 t = 0;
        int256 newt = 1;
        int256 r = int256(n);
        int256 newr = int256(a);
        
        while (newr != 0) {
            int256 quotient = r / newr;
            
            (t, newt) = (newt, t - quotient * newt);
            (r, newr) = (newr, r - quotient * newr);
        }
        
        if (r > 1) revert InvalidScalar();
        if (t < 0) t = t + int256(n);
        
        return uint256(t);
    }
} 