// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool5.sol";
import {Bodhi} from "../../src/Bodhi.sol";
import {ERC1155TokenReceiver} from "../../src/peripheral/ERC1155TokenReceiver.sol";

contract Wishpool5Test is Test, ERC1155TokenReceiver {
    Wishpool5 public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    string arTxId = "testArTxId";

    uint256 public openMissionId;
    uint256 public targetedMissionId;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_SHARE = 1 ether;

    event CreateMission(uint256 indexed missionId, address indexed creator, address indexed solver);
    event CreateSubmission(uint256 indexed missionId, address indexed solver, uint256 submissionId);
    event CompleteMission(
        uint256 indexed missionId,
        address indexed solver,
        uint256 indexed submissionId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool5(address(bodhi));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        (openMissionId, targetedMissionId) = _createTestMissions();
    }

    // ==================== Create Mission Tests ====================

    function test_CreateMission() public {
        uint256 newMissionId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateMission(newMissionId, alice, address(0));
        
        vm.prank(alice);
        wishpool.createMission("newMissionTxId", address(0));

        (address creator, address solver, bool completed, uint256 submission) = wishpool.missions(newMissionId);
        assertEq(creator, alice);
        assertEq(solver, address(0));
        assertFalse(completed);
        assertEq(submission, 0);
    }

    // ==================== Create Submission Tests ====================

    function test_CreateSubmissionOpenMission() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateSubmission(openMissionId, bob, submissionId);
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");

        assertEq(wishpool.submissionToMission(submissionId), openMissionId);
        assertEq(wishpool.submissionToCreator(submissionId), bob);
        (,, bool completed,) = wishpool.missions(openMissionId);
        assertFalse(completed);
    }

    function test_CreateSubmissionTargetedMission() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateSubmission(targetedMissionId, bob, submissionId);
        vm.prank(bob);
        wishpool.createSubmission(targetedMissionId, "submissionTxId");

        assertEq(wishpool.submissionToMission(submissionId), targetedMissionId);
        assertEq(wishpool.submissionToCreator(submissionId), bob);
        (,, bool completed,) = wishpool.missions(targetedMissionId);
        assertFalse(completed);
    }

    function test_CreateSubmissionMultipleSubmissions() public {
        uint256 firstSubmissionId = bodhi.assetIndex();
        uint256 secondSubmissionId = firstSubmissionId + 1;

        vm.startPrank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId1");
        wishpool.createSubmission(openMissionId, "submissionTxId2");
        vm.stopPrank();

        assertEq(wishpool.submissionToMission(firstSubmissionId), openMissionId);
        assertEq(wishpool.submissionToCreator(firstSubmissionId), bob);
        assertEq(wishpool.submissionToMission(secondSubmissionId), openMissionId);
        assertEq(wishpool.submissionToCreator(secondSubmissionId), bob);
    }

    function test_CreateSubmissionEmitsCorrectEvent() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateSubmission(openMissionId, bob, submissionId);
        
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");
    }

    function testFail_CreateSubmissionTargetedMissionUnauthorized() public {
        vm.prank(alice);
        wishpool.createSubmission(targetedMissionId, "submissionTxId");
    }

    function testFail_CreateSubmissionForNonExistentMission() public {
        uint256 nonExistentMissionId = 9999;
        vm.prank(bob);
        wishpool.createSubmission(nonExistentMissionId, "submissionTxId");
    }

    function testFail_CreateSubmissionForCompletedMission() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");
        vm.prank(alice);
        wishpool.completeMission(openMissionId, submissionId);

        vm.prank(charlie);
        wishpool.createSubmission(openMissionId, "anotherSubmissionTxId");
    }

    // ==================== Complete Mission Tests ====================

    function test_CompleteMissionOpenMission() public {
        uint256 fundAmount = 1 ether;
        _addFundsToMission(bob, openMissionId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openMissionId, expectedTokenAmount);

        uint256 bobBalanceBefore = bob.balance;
        
        vm.expectEmit(true, true, true, true);
        emit CompleteMission(openMissionId, bob, submissionId, expectedTokenAmount, expectedEthAmount);

        vm.prank(alice);
        wishpool.completeMission(openMissionId, submissionId);

        _assertMissionCompleted(openMissionId, bob, expectedEthAmount, bobBalanceBefore, submissionId);
    }

    function test_CompleteMissionTargetedMission() public {
        uint256 fundAmount = 1 ether;
        _addFundsToMission(alice, targetedMissionId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(targetedMissionId, "submissionTxId");

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(targetedMissionId, expectedTokenAmount);

        vm.expectEmit(true, true, true, true);
        emit CompleteMission(targetedMissionId, bob, submissionId, expectedTokenAmount, expectedEthAmount);

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        wishpool.completeMission(targetedMissionId, submissionId);

        _assertMissionCompleted(targetedMissionId, bob, expectedEthAmount, bobBalanceBefore, submissionId);
    }

    function test_CompleteMissionWithNoFunds() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        wishpool.completeMission(openMissionId, submissionId);

        (,, bool completed, uint256 winningSubmission) = wishpool.missions(openMissionId);
        assertTrue(completed);
        assertEq(winningSubmission, submissionId);
        assertEq(bob.balance, bobBalanceBefore, "Bob's balance should not change when there are no funds");
    }

    function testFail_CompleteMissionOpenMissionUnauthorized() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");

        vm.prank(charlie);
        wishpool.completeMission(openMissionId, submissionId);
    }

    function testFail_CompleteMissionTargetedMissionUnauthorized() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(targetedMissionId, "submissionTxId");

        vm.prank(charlie);
        wishpool.completeMission(targetedMissionId, submissionId);
    }

    function testFail_CompleteMissionNonExistentMission() public {
        vm.prank(alice);
        wishpool.completeMission(999, 0);
    }

    function testFail_CompleteMissionWithoutSubmission() public {
        vm.prank(alice);
        wishpool.completeMission(openMissionId, 999);
    }

    function testFail_CompleteMissionAlreadyCompletedMission() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createSubmission(openMissionId, "submissionTxId");

        vm.startPrank(alice);
        wishpool.completeMission(openMissionId, submissionId);
        wishpool.completeMission(openMissionId, submissionId);
        vm.stopPrank();
    }

    function testFail_CompleteMissionWithUnsubmittedSubmission() public {
        vm.prank(alice);
        wishpool.completeMission(openMissionId, 0);
    }

    // ==================== Helper Functions ====================

    function _createTestMissions() internal returns (uint256, uint256) {
        vm.startPrank(alice);
        
        // Create a dummy mission to ensure openMissionId is not 0
        wishpool.createMission("dummyMissionTxId", address(0));
        
        uint256 _openMissionId = bodhi.assetIndex();
        wishpool.createMission("openMissionTxId", address(0));

        uint256 _targetedMissionId = bodhi.assetIndex();
        wishpool.createMission("targetedMissionTxId", bob);
        vm.stopPrank();
        return (_openMissionId, _targetedMissionId);
    }

    function _addFundsToMission(address funder, uint256 missionId, uint256 fundAmount) internal {
        vm.startPrank(funder);
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(missionId, fundAmount);
        bodhi.buy{value: buyPrice}(missionId, fundAmount);
        bodhi.safeTransferFrom(funder, address(wishpool), missionId, fundAmount, "");
        vm.stopPrank();
    }

    function _assertMissionCompleted(uint256 missionId, address solver, uint256 expectedEthAmount, uint256 solverBalanceBefore, uint256 expectedSubmissionId) internal view {
        (,, bool completed, uint256 winningSubmission) = wishpool.missions(missionId);
        assertTrue(completed, "Mission should be marked as completed");
        assertEq(winningSubmission, expectedSubmissionId, "Winning submission should be recorded");
        assertEq(solver.balance, solverBalanceBefore + expectedEthAmount, "Solver should receive the expected ETH amount");
    }
}