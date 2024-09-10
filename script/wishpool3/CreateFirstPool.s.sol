// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {Wishpool3} from "../../src/Wishpool/Wishpool3.sol";
import {IBodhi} from "../../src/interface/IBodhi.sol";

contract CreateFirstPool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable wishpoolAddress = payable(vm.envAddress("WISHPOOL_ADDRESS"));
        string memory arTxId = vm.envString("AR_TX_ID");

        vm.startBroadcast(deployerPrivateKey);
        
        Wishpool3 wishpool = Wishpool3(wishpoolAddress);
        IBodhi bodhi = wishpool.BODHI();

        // Create a regular pool (solver is address(0))
        uint256 poolId = bodhi.assetIndex();
        wishpool.createPool(arTxId, address(0));

        console.log("First pool created with ID:", poolId);

        // Verify the pool
        (address creator, address solver, bool completed) = wishpool.pools(poolId);
        console.log("Pool creator:", creator);
        console.log("Pool solver:", solver);
        console.log("Pool completed:", completed);

        vm.stopBroadcast();
    }
}
