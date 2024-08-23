// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./WishpoolBase.t.sol";

contract WishpoolCreateTest is WishpoolBaseTest {
    event Create(uint256 indexed poolId, address indexed creator, address indexed solver);

    function setUp() public override {
        super.setUp();
    }

    function test_CreateRegularPool() public {
        _testCreatePool(address(0));
    }

    function test_CreateSpecialPool() public {
        _testCreatePool(bob);
    }

    function _testCreatePool(address solver) internal {
        vm.startPrank(alice);

        uint256 assetId = bodhi.assetIndex();

        vm.expectEmit(true, true, true, true);
        emit Create(assetId, alice, solver);

        wishpool.createPool(arTxId, solver);
        assertEq(bodhi.assetIndex(), assetId + 1, "Asset index should increment");

        // Check Pool struct
        (address creator, address poolSolver, bool completed) = wishpool.pools(assetId);
        assertEq(creator, alice, "Pool creator should be alice");
        assertEq(poolSolver, solver, "Pool solver should match the input");
        assertFalse(completed, "Pool should not be completed initially");

        // Check Bodhi asset
        (uint256 id, string memory storedArTxId, address assetCreator) = bodhi.assets(assetId);
        assertEq(id, assetId, "Asset ID should match");
        assertEq(storedArTxId, arTxId, "ArTxId should match");
        assertEq(assetCreator, address(wishpool), "Asset creator should be the Wishpool contract");

        // Check if Wishpool received the initial token balance
        assertEq(
            bodhi.balanceOf(address(wishpool), assetId),
            1 ether,
            "Wishpool should have received the initial token balance"
        );

        vm.stopPrank();
    }
}
