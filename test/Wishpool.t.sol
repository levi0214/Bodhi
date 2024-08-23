// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/Wishpool/Wishpool.sol";
import "../src/Bodhi.sol";
import "../src/peripheral/ERC1155TokenReceiver.sol";

contract WishpoolTest is Test, ERC1155TokenReceiver {
    Wishpool public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);

    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool(address(bodhi));
        vm.deal(alice, 100 ether);
    }

    function testCreatePool() public {
        vm.startPrank(alice);

        string memory arTxId = "testArTxId";
        address solver = address(0x2);

        uint256 initialAssetIndex = bodhi.assetIndex();

        wishpool.createPool(arTxId, solver);

        assertEq(bodhi.assetIndex(), initialAssetIndex + 1, "Asset index should increment");

        (address creator, address poolSolver, bool completed) = wishpool.pools(initialAssetIndex);
        assertEq(creator, alice, "Pool creator should be alice");
        assertEq(poolSolver, solver, "Pool solver should match the input");
        assertFalse(completed, "Pool should not be completed initially");

        // Check if the asset was created in Bodhi
        (uint256 id, string memory storedArTxId, address assetCreator) = bodhi.assets(initialAssetIndex);
        assertEq(id, initialAssetIndex, "Asset ID should match");
        assertEq(storedArTxId, arTxId, "ArTxId should match");
        assertEq(assetCreator, address(wishpool), "Asset creator should be the Wishpool contract");

        // Check if Wishpool received the initial token balance
        assertEq(
            bodhi.balanceOf(address(wishpool), initialAssetIndex),
            1 ether,
            "Wishpool should have received the initial token balance"
        );

        vm.stopPrank();
    }
}
