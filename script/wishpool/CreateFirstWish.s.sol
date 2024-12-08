// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {Wishpool} from "../../src/Wishpool/Wishpool.sol";
import {IBodhi} from "../../src/interface/IBodhi.sol";

contract CreateFirstWish is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable wishpoolAddress = payable(vm.envAddress("WISHPOOL_ADDRESS"));
        string memory arTxId = vm.envString("AR_TX_ID");

        vm.startBroadcast(deployerPrivateKey);
        
        Wishpool wishpool = Wishpool(wishpoolAddress);
        IBodhi bodhi = wishpool.BODHI();

        // Create an open wish (solver is address(0))
        uint256 wishId = bodhi.assetIndex();
        wishpool.createWish(arTxId, address(0));

        console.log("First wish created with ID:", wishId);

        // Verify the wish
        (address creator, address solver) = wishpool.wishes(wishId);
        console.log("Wish creator:", creator);
        console.log("Wish solver:", solver);

        vm.stopBroadcast();
    }
}
