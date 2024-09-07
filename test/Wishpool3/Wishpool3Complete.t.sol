// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Wishpool3Base.t.sol";

// test submission and complete process of wishpool3

contract Wishpool3CompleteTest is Wishpool3BaseTest {
    uint256 public regularPoolId;
    uint256 public specialPoolId;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_SHARE = 1 ether;

    event SubmitSolution(uint256 indexed poolId, address indexed solver, uint256 solutionId);
    event Complete(uint256 indexed poolId, address indexed solver, uint256 indexed solutionId, uint256 amount);

    function setUp() public override {
        super.setUp();
        (regularPoolId, specialPoolId) = _createTestPools();
    }

    function test_SubmitSolutionRegularPool() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(regularPoolId, solutionId);

        (,, bool completed) = wishpool.pools(regularPoolId);
        assertFalse(completed, "Pool should not be completed after solution submission");
    }

    function test_SubmitSolutionSpecialPool() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(specialPoolId, solutionId);

        (,, bool completed) = wishpool.pools(specialPoolId);
        assertFalse(completed, "Pool should not be completed after solution submission");
    }

    function testFail_SubmitSolutionSpecialPoolUnauthorized() public {
        uint256 solutionId = _createSolution(alice);
        vm.prank(alice);
        wishpool.submitSolution(specialPoolId, solutionId);
    }

    function test_CompleteRegularPool() public {
        uint256 fundAmount = 1 ether;
        _addFundsToPool(bob, regularPoolId, fundAmount);

        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(regularPoolId, solutionId);

        vm.expectEmit(true, true, true, true);
        emit Complete(regularPoolId, bob, solutionId, INITIAL_SHARE + fundAmount);

        vm.prank(alice);
        wishpool.complete(regularPoolId, solutionId);

        _assertPoolCompleted(regularPoolId, bob, INITIAL_SHARE + fundAmount);
    }

    function test_CompleteSpecialPool() public {
        uint256 fundAmount = 1 ether;
        _addFundsToPool(alice, specialPoolId, fundAmount);

        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(specialPoolId, solutionId);

        vm.expectEmit(true, true, true, true);
        emit Complete(specialPoolId, bob, solutionId, INITIAL_SHARE + fundAmount);

        vm.prank(bob);
        wishpool.complete(specialPoolId, solutionId);

        _assertPoolCompleted(specialPoolId, bob, INITIAL_SHARE + fundAmount);
    }

    function testFail_CompleteRegularPoolUnauthorized() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.complete(regularPoolId, solutionId);
    }

    function testFail_CompleteSpecialPoolUnauthorized() public {
        uint256 solutionId = _createSolution(alice);
        vm.prank(alice);
        wishpool.complete(specialPoolId, solutionId);
    }

    function testFail_CompleteNonExistentPool() public {
        uint256 solutionId = _createSolution(alice);
        vm.prank(alice);
        wishpool.complete(999, solutionId);
    }

    function testFail_CompleteWithoutSolution() public {
        vm.prank(alice);
        wishpool.complete(regularPoolId, 999);
    }

    function testFail_CompleteAlreadyCompletedPool() public {
        uint256 solutionId = _createSolution(bob);
        vm.startPrank(bob);
        wishpool.submitSolution(regularPoolId, solutionId);
        vm.stopPrank();

        vm.startPrank(alice);
        wishpool.complete(regularPoolId, solutionId);
        wishpool.complete(regularPoolId, solutionId);
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

    function _createSolution(address creator) internal returns (uint256) {
        uint256 solutionId = bodhi.assetIndex();
        vm.prank(creator);
        bodhi.create("solutionTxId");
        return solutionId;
    }
}
