// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Wishpool2Base.t.sol";

// test submission and complete process of wishpool2

contract Wishpool2CompleteTest is Wishpool2BaseTest {
    uint256 public regularPoolId;
    uint256 public specialPoolId;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_SHARE = 1 ether;

    event SubmitSolution(uint256 indexed poolId, address indexed solver, string arTxId);
    event Complete(uint256 indexed poolId, address indexed solver, uint256 amount);

    function setUp() public override {
        super.setUp();
        (regularPoolId, specialPoolId) = _createTestPools();
    }

    function test_SubmitSolutionRegularPool() public {
        vm.prank(bob);
        wishpool.submitSolution(regularPoolId, "solutionTxId");

        (,, bool completed) = wishpool.pools(regularPoolId);
        assertFalse(completed, "Pool should not be completed after solution submission");
    }

    function test_SubmitSolutionSpecialPool() public {
        vm.prank(bob);
        wishpool.submitSolution(specialPoolId, "solutionTxId");

        (,, bool completed) = wishpool.pools(specialPoolId);
        assertFalse(completed, "Pool should not be completed after solution submission");
    }

    function testFail_SubmitSolutionSpecialPoolUnauthorized() public {
        vm.prank(alice);
        wishpool.submitSolution(specialPoolId, "solutionTxId");
    }

    function test_CompleteRegularPool() public {
        uint256 fundAmount = 1 ether;
        _addFundsToPool(bob, regularPoolId, fundAmount);

        vm.prank(bob);
        wishpool.submitSolution(regularPoolId, "solutionTxId");

        vm.expectEmit(true, true, true, true);
        emit Complete(regularPoolId, bob, INITIAL_SHARE + fundAmount);

        vm.prank(alice);
        wishpool.complete(regularPoolId, 0);

        _assertPoolCompleted(regularPoolId, bob, INITIAL_SHARE + fundAmount);
    }

    function test_CompleteSpecialPool() public {
        uint256 fundAmount = 1 ether;
        _addFundsToPool(alice, specialPoolId, fundAmount);

        vm.prank(bob);
        wishpool.submitSolution(specialPoolId, "solutionTxId");

        vm.expectEmit(true, true, true, true);
        emit Complete(specialPoolId, bob, INITIAL_SHARE + fundAmount);

        vm.prank(bob);
        wishpool.complete(specialPoolId, 0);

        _assertPoolCompleted(specialPoolId, bob, INITIAL_SHARE + fundAmount);
    }

    function testFail_CompleteRegularPoolUnauthorized() public {
        vm.prank(bob);
        wishpool.complete(regularPoolId, 0);
    }

    function testFail_CompleteSpecialPoolUnauthorized() public {
        vm.prank(alice);
        wishpool.complete(specialPoolId, 0);
    }

    function testFail_CompleteNonExistentPool() public {
        vm.prank(alice);
        wishpool.complete(999, 0);
    }

    function testFail_CompleteWithoutSolution() public {
        vm.prank(alice);
        wishpool.complete(regularPoolId, 0);
    }

    function testFail_CompleteAlreadyCompletedPool() public {
        vm.startPrank(bob);
        wishpool.submitSolution(regularPoolId, "solutionTxId");
        vm.stopPrank();

        vm.startPrank(alice);
        wishpool.complete(regularPoolId, 0);
        wishpool.complete(regularPoolId, 0);
        vm.stopPrank();
    }

    function _createTestPools() internal returns (uint256, uint256) {
        vm.startPrank(alice);
        uint256 _regularPoolId = bodhi.assetIndex();
        wishpool.createPool("regularPoolTxId", address(0));

        uint256 _specialPoolId = bodhi.assetIndex();
        wishpool.createPool("specialPoolTxId", bob);
        vm.stopPrank();
        return (_regularPoolId, _specialPoolId);
    }

    function _addFundsToPool(address funder, uint256 poolId, uint256 fundAmount) internal {
        vm.startPrank(funder);
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(poolId, fundAmount);
        bodhi.buy{value: buyPrice}(poolId, fundAmount);
        bodhi.safeTransferFrom(funder, address(wishpool), poolId, fundAmount, "");
        vm.stopPrank();
    }

    function _assertPoolCompleted(uint256 poolId, address solver, uint256 expectedBalance) internal view {
        (,, bool completed) = wishpool.pools(poolId);
        assertTrue(completed, "Pool should be marked as completed");
        assertEq(bodhi.balanceOf(solver, poolId), expectedBalance, "Solver should receive the expected balance");
        assertEq(bodhi.balanceOf(address(wishpool), poolId), 0, "Wishpool balance should be zero after completion");
    }
}
