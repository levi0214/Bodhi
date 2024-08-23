// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./WishpoolBase.t.sol";

contract WishpoolCompleteTest is WishpoolBaseTest {
    uint256 public regularPoolId;
    uint256 public specialPoolId;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_SHARE = 1 ether;

    event Complete(uint256 indexed poolId, address indexed solver, uint256 amount);

    function setUp() public override {
        super.setUp();
        
        vm.startPrank(alice);
        regularPoolId = bodhi.assetIndex();
        wishpool.createPool("regularPoolTxId", address(0));
        
        specialPoolId = bodhi.assetIndex();
        wishpool.createPool("specialPoolTxId", bob);
        vm.stopPrank();
    }

    function test_CompleteRegularPool() public {
        // Add some funds to the pool
        vm.startPrank(bob);
        uint256 fundAmount = 1 ether;
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(regularPoolId, fundAmount);
        bodhi.buy{value: buyPrice}(regularPoolId, fundAmount);
        bodhi.safeTransferFrom(bob, address(wishpool), regularPoolId, fundAmount, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit Complete(regularPoolId, bob, INITIAL_SHARE + fundAmount);
        wishpool.complete(regularPoolId, bob);
        vm.stopPrank();

        (,, bool completed) = wishpool.pools(regularPoolId);
        assertTrue(completed, "Pool should be marked as completed");
        assertEq(bodhi.balanceOf(bob, regularPoolId), INITIAL_SHARE + fundAmount, "Solver should receive the pool balance plus initial share");
        assertEq(bodhi.balanceOf(address(wishpool), regularPoolId), 0, "Wishpool balance should be zero after completion");
    }

    function test_CompleteSpecialPool() public {
        // Add some funds to the pool
        vm.startPrank(alice);
        uint256 fundAmount = 1 ether;
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(specialPoolId, fundAmount);
        bodhi.buy{value: buyPrice}(specialPoolId, fundAmount);
        bodhi.safeTransferFrom(alice, address(wishpool), specialPoolId, fundAmount, "");
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Complete(specialPoolId, bob, INITIAL_SHARE + fundAmount);
        wishpool.complete(specialPoolId, bob);
        vm.stopPrank();

        (,, bool completed) = wishpool.pools(specialPoolId);
        assertTrue(completed, "Pool should be marked as completed");
        assertEq(bodhi.balanceOf(bob, specialPoolId), INITIAL_SHARE + fundAmount, "Solver should receive the pool balance plus initial share");
        assertEq(bodhi.balanceOf(address(wishpool), specialPoolId), 0, "Wishpool balance should be zero after completion");
    }

    function testFail_CompleteRegularPoolUnauthorized() public {
        vm.prank(bob);
        wishpool.complete(regularPoolId, bob);
    }

    function testFail_CompleteSpecialPoolUnauthorized() public {
        vm.prank(alice);
        wishpool.complete(specialPoolId, alice);
    }

    function testFail_CompleteNonExistentPool() public {
        vm.prank(alice);
        wishpool.complete(999, alice);
    }

    function test_CompleteEmptyPool() public {
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit Complete(regularPoolId, bob, INITIAL_SHARE);
        wishpool.complete(regularPoolId, bob);
        vm.stopPrank();

        (,, bool completed) = wishpool.pools(regularPoolId);
        assertTrue(completed, "Pool should be marked as completed even if empty");
        assertEq(bodhi.balanceOf(bob, regularPoolId), INITIAL_SHARE, "Solver should receive the initial share");
    }

    function testFail_CompleteAlreadyCompletedPool() public {
        vm.prank(alice);
        wishpool.complete(regularPoolId, bob);

        vm.prank(alice);
        wishpool.complete(regularPoolId, bob);
    }

    function test_CompleteLargePool() public {
        // Add a large amount of funds to the pool
        vm.deal(bob, 21000 ether);
        vm.startPrank(bob);
        uint256 fundAmount = 1000 ether;
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(regularPoolId, fundAmount);
        bodhi.buy{value: buyPrice}(regularPoolId, fundAmount);
        bodhi.safeTransferFrom(bob, address(wishpool), regularPoolId, fundAmount, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit Complete(regularPoolId, bob, INITIAL_SHARE + fundAmount);
        wishpool.complete(regularPoolId, bob);
        vm.stopPrank();

        assertEq(bodhi.balanceOf(bob, regularPoolId), INITIAL_SHARE + fundAmount, "Solver should receive the large pool balance plus initial share");
    }
}