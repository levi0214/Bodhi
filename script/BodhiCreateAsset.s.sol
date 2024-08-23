// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../src/Bodhi.sol";

contract CreateAsset is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bodhiAddress = vm.envAddress("BODHI_ADDRESS");
        string memory arTxId = vm.envString("AR_TX_ID");

        vm.startBroadcast(deployerPrivateKey);

        Bodhi bodhi = Bodhi(bodhiAddress);
        
        uint256 assetIndexBefore = bodhi.assetIndex();
        console.log("Asset index before creation:", assetIndexBefore);

        bodhi.create(arTxId);

        uint256 assetIndexAfter = bodhi.assetIndex();
        console.log("Asset index after creation:", assetIndexAfter);
        console.log("New asset created with ID:", assetIndexAfter - 1);

        // Verify the asset
        (uint256 id, string memory storedArTxId, address creator) = bodhi.assets(assetIndexAfter - 1);
        console.log("Asset ID:", id);
        console.log("Stored ArTxId:", storedArTxId);
        console.log("Creator:", creator);

        vm.stopBroadcast();
    }
}