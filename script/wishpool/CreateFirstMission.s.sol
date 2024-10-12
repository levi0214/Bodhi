// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {Wishpool5} from "../../src/Wishpool/Wishpool5.sol";
import {IBodhi} from "../../src/interface/IBodhi.sol";

contract CreateFirstMission is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable wishpoolAddress = payable(vm.envAddress("WISHPOOL_ADDRESS"));
        string memory arTxId = vm.envString("AR_TX_ID");

        vm.startBroadcast(deployerPrivateKey);
        
        Wishpool5 wishpool = Wishpool5(wishpoolAddress);
        IBodhi bodhi = wishpool.BODHI();

        // Create a open mission (solver is address(0))
        uint256 missionId = bodhi.assetIndex();
        wishpool.createMission(arTxId, address(0));

        console.log("First mission created with ID:", missionId);

        // Verify the mission
        (address creator, address solver, bool completed, uint256 submission) = wishpool.missions(missionId);
        console.log("Mission creator:", creator);
        console.log("Mission solver:", solver);
        console.log("Mission completed:", completed);
        console.log("Mission submission:", submission);

        vm.stopBroadcast();
    }
}
