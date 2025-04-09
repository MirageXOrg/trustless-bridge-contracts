// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {TrustlessBTC} from "../src/tBTC.sol";

contract CounterTest is Test {
    TrustlessBTC public tBTC;

    function setUp() public {
        tBTC = new TrustlessBTC(hex"000000000000000000000000000000000000000000", address(0));
    }
}
