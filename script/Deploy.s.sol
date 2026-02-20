// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/UnicornMarket.sol";

contract DeployUnicornMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        UnicornMarket market = new UnicornMarket();
        vm.stopBroadcast();

        console.log("UnicornMarket deployed to:", address(market));
        console.log("Verify on Etherscan:");
        console.log("  forge verify-contract", address(market), "src/UnicornMarket.sol:UnicornMarket --chain mainnet");
    }
}
