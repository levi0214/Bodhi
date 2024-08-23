// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../src/Bodhi.sol";

contract DeployBodhi is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Bodhi bodhi = new Bodhi();

        console.log("Bodhi deployed at:", address(bodhi));

        vm.stopBroadcast();
    }
}