// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {Wishpool} from "../../src/Wishpool/Wishpool.sol";

contract DeployWishpool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        address bodhiAddress = vm.envAddress("BODHI_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        
        // deploy
        Wishpool wishpool = new Wishpool(bodhiAddress, treasuryAddress);
        console.log("Wishpool deployed at:", address(wishpool));

        // deployment check
        address bodhi = address(wishpool.BODHI());
        require(bodhi == bodhiAddress, "Deployment failed: BODHI address mismatch");
        console.log("Deployment verified");
        
        vm.stopBroadcast();
    }
}
