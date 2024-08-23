// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/Bodhi.sol";
import "solmate/tokens/ERC1155.sol";

contract BodhiTest is Test, ERC1155TokenReceiver {
    Bodhi public bodhi;
    address public alice = address(0x1);

    function setUp() public {
        bodhi = new Bodhi();
        vm.deal(alice, 100 ether);
    }

    function testInitialAssetIndex() public view {
        assertEq(bodhi.assetIndex(), 0, "Initial asset index should be 0");
    }

    function testCreateAsset() public {
        vm.startPrank(alice);
        string memory arTxId = "testArTxId";
        bodhi.create(arTxId);
        assertEq(bodhi.assetIndex(), 1, "Asset index should be 1 after creation");
        vm.stopPrank();
    }
}
