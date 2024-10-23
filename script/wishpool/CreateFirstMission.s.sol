// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {Wishpool6} from "../../src/Wishpool/Wishpool6.sol";
import {IBodhi} from "../../src/interface/IBodhi.sol";

contract CreateFirstMission is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable wishpoolAddress = payable(vm.envAddress("WISHPOOL_ADDRESS"));
        string memory arTxId = vm.envString("AR_TX_ID");

        vm.startBroadcast(deployerPrivateKey);
        
        Wishpool6 wishpool = Wishpool6(wishpoolAddress);
        IBodhi bodhi = wishpool.BODHI();

        // Create a open mission (solver is address(0))
        uint256 wishId = bodhi.assetIndex();
        wishpool.createWish(arTxId, address(0));

        console.log("First mission created with ID:", wishId);

        // Verify the mission
        (address creator, address solver, bool isOpen) = wishpool.wishes(wishId);
        console.log("Wish creator:", creator);
        console.log("Wish solver:", solver);
        console.log("Wish is open:", isOpen);

        vm.stopBroadcast();
    }
}
