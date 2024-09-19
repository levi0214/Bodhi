// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool4.sol";
import "../../src/Bodhi.sol";
import "../../src/peripheral/ERC1155TokenReceiver.sol";

// Updated the Complete event to include tokenAmount and ethAmount.
// Modified the _assertPoolCompleted function to check for ETH balance changes instead of token balance changes.
// Added a test for completing a pool with no funds (test_CompleteWithNoFunds).
// Added a test for completing a pool with an unsubmitted solution (testFail_CompleteWithUnsubmittedSolution).
// Updated the test_SubmitSolutionRegularPool and test_SubmitSolutionSpecialPool to check the solutionToPool mapping instead of the removed solutions array.
// Modified the test_CompleteRegularPool and test_CompleteSpecialPool to account for the new share selling mechanism and ETH transfer.
// Removed tests related to the getSolutions function, as it no longer exists in Wishpool4.

contract Wishpool4Test is Test, ERC1155TokenReceiver {
    Wishpool4 public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    string arTxId = "testArTxId";

    uint256 public regularPoolId;
    uint256 public specialPoolId;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_SHARE = 1 ether;

    event Create(uint256 indexed poolId, address indexed creator, address indexed solver);
    event SubmitSolution(uint256 indexed poolId, address indexed solver, uint256 solutionId);
    event Complete(
        uint256 indexed poolId,
        address indexed solver,
        uint256 indexed solutionId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool4(address(bodhi));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        (regularPoolId, specialPoolId) = _createTestPools();
    }

    function test_CreatePool() public {
        uint256 newPoolId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit Create(newPoolId, alice, address(0));
        
        vm.prank(alice);
        wishpool.createPool("newPoolTxId", address(0));

        (address creator, address solver, bool completed) = wishpool.pools(newPoolId);
        assertEq(creator, alice);
        assertEq(solver, address(0));
        assertFalse(completed);
    }

    function test_SubmitSolutionRegularPool() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(regularPoolId, solutionId);

        assertEq(wishpool.solutionToPool(solutionId), regularPoolId);
        (,, bool completed) = wishpool.pools(regularPoolId);
        assertFalse(completed);
    }

    function test_SubmitSolutionSpecialPool() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(specialPoolId, solutionId);

        assertEq(wishpool.solutionToPool(solutionId), specialPoolId);
        (,, bool completed) = wishpool.pools(specialPoolId);
        assertFalse(completed);
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

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(regularPoolId, expectedTokenAmount);

        uint256 bobBalanceBefore = bob.balance;
        
        vm.expectEmit(true, true, true, true);
        emit Complete(regularPoolId, bob, solutionId, expectedTokenAmount, expectedEthAmount);

        vm.prank(alice);
        wishpool.complete(regularPoolId, solutionId);

        _assertPoolCompleted(regularPoolId, bob, expectedEthAmount, bobBalanceBefore);
    }

    function test_CompleteSpecialPool() public {
        uint256 fundAmount = 1 ether;
        _addFundsToPool(alice, specialPoolId, fundAmount);

        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(specialPoolId, solutionId);

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(specialPoolId, expectedTokenAmount);

        vm.expectEmit(true, true, true, true);
        emit Complete(specialPoolId, bob, solutionId, expectedTokenAmount, expectedEthAmount);

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        wishpool.complete(specialPoolId, solutionId);

        _assertPoolCompleted(specialPoolId, bob, expectedEthAmount, bobBalanceBefore);
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

    function test_CompleteWithNoFunds() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(bob);
        wishpool.submitSolution(regularPoolId, solutionId);

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        wishpool.complete(regularPoolId, solutionId);

        (,, bool completed) = wishpool.pools(regularPoolId);
        assertTrue(completed);
        assertEq(bob.balance, bobBalanceBefore, "Bob's balance should not change when there are no funds");
    }

    function testFail_CompleteWithUnsubmittedSolution() public {
        uint256 solutionId = _createSolution(bob);
        vm.prank(alice);
        wishpool.complete(regularPoolId, solutionId);
    }

    function _createTestPools() internal returns (uint256, uint256) {
        vm.startPrank(alice);
        
        // Create a dummy pool to ensure regularPoolId is not 0
        wishpool.createPool("dummyPoolTxId", address(0));
        
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

    function _assertPoolCompleted(uint256 poolId, address solver, uint256 expectedEthAmount, uint256 solverBalanceBefore) internal view {
        (,, bool completed) = wishpool.pools(poolId);
        assertTrue(completed, "Pool should be marked as completed");
        assertEq(solver.balance, solverBalanceBefore + expectedEthAmount, "Solver should receive the expected ETH amount");
    }

    function _createSolution(address creator) internal returns (uint256) {
        uint256 solutionId = bodhi.assetIndex();
        vm.prank(creator);
        bodhi.create("solutionTxId");
        return solutionId;
    }
}