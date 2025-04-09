// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/TBTC.sol";

contract DeployTBTC is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        bytes21 roflAppID = bytes21(vm.envBytes("ROFL_APP_ID"));
        address oracle = vm.envAddress("ORACLE_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        TrustlessBTC tbtc = new TrustlessBTC(roflAppID, oracle);

        vm.stopBroadcast();

        console.log("TrustlessBTC deployed to:", address(tbtc));
        console.log("Bitcoin address:", tbtc.bitcoinAddress());
        console.log("Public key:", string(abi.encodePacked(tbtc.publicKey())));
    }
} 