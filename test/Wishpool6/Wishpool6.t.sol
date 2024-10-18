// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool6.sol";
import {Bodhi} from "../../src/Bodhi.sol";
import {ERC1155TokenReceiver} from "../../src/peripheral/ERC1155TokenReceiver.sol";

contract Wishpool6Test is Test, ERC1155TokenReceiver {
    Wishpool6 public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    string arTxId = "testArTxId";

    uint256 public openWishId;
    uint256 public targetedWishId;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_SHARE = 1 ether;

    event CreateWish(uint256 indexed wishId, address indexed creator, address indexed solver);
    event CreateResponse(uint256 indexed wishId, address indexed solver, uint256 responseId);
    event CloseWish(
        uint256 indexed wishId,
        address indexed solver,
        uint256 indexed responseId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool6(address(bodhi));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        (openWishId, targetedWishId) = _createTestWishes();
    }

    // ==================== Create Wish Tests ====================

    function test_CreateWish() public {
        uint256 newWishId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateWish(newWishId, alice, address(0));
        
        vm.prank(alice);
        wishpool.createWish("newWishTxId", address(0));

        (address creator, address solver, bool isOpen) = wishpool.wishes(newWishId);
        assertEq(creator, alice);
        assertEq(solver, address(0));
        assertTrue(isOpen);
    }

    // ==================== Create Response Tests ====================

    function test_CreateResponseOpenWish() public {
        uint256 responseId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateResponse(openWishId, bob, responseId);
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        (address creator, uint256 wishId, bool isRewarded) = wishpool.responses(responseId);
        assertEq(creator, bob);
        assertEq(wishId, openWishId);
        assertFalse(isRewarded);
    }

    function test_CreateResponseTargetedWish() public {
        uint256 responseId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateResponse(targetedWishId, bob, responseId);
        vm.prank(bob);
        wishpool.createResponse(targetedWishId, "responseTxId");

        (address creator, uint256 wishId, bool isRewarded) = wishpool.responses(responseId);
        assertEq(creator, bob);
        assertEq(wishId, targetedWishId);
        assertFalse(isRewarded);
    }

    function test_CreateResponseMultipleResponses() public {
        uint256 firstResponseId = bodhi.assetIndex();
        uint256 secondResponseId = firstResponseId + 1;

        vm.startPrank(bob);
        wishpool.createResponse(openWishId, "responseTxId1");
        wishpool.createResponse(openWishId, "responseTxId2");
        vm.stopPrank();

        (address creator1, uint256 wishId1, bool isRewarded1) = wishpool.responses(firstResponseId);
        (address creator2, uint256 wishId2, bool isRewarded2) = wishpool.responses(secondResponseId);

        assertEq(creator1, bob);
        assertEq(wishId1, openWishId);
        assertFalse(isRewarded1);
        assertEq(creator2, bob);
        assertEq(wishId2, openWishId);
        assertFalse(isRewarded2);
    }

    function test_CreateResponseEmitsCorrectEvent() public {
        uint256 responseId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit CreateResponse(openWishId, bob, responseId);
        
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");
    }

    function testFail_CreateResponseTargetedWishUnauthorized() public {
        vm.prank(alice);
        wishpool.createResponse(targetedWishId, "responseTxId");
    }

    function testFail_CreateResponseForNonExistentWish() public {
        uint256 nonExistentWishId = 9999;
        vm.prank(bob);
        wishpool.createResponse(nonExistentWishId, "responseTxId");
    }

    function testFail_CreateResponseForClosedWish() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");
        vm.prank(alice);
        wishpool.closeWish(openWishId, responseId);

        vm.prank(charlie);
        wishpool.createResponse(openWishId, "anotherResponseTxId");
    }

    // ==================== Close Wish Tests ====================

    function test_CloseWishOpenWish() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(bob, openWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, expectedTokenAmount);

        uint256 bobBalanceBefore = bob.balance;
        
        vm.expectEmit(true, true, true, true);
        emit CloseWish(openWishId, bob, responseId, expectedTokenAmount, expectedEthAmount);

        vm.prank(alice);
        wishpool.closeWish(openWishId, responseId);

        _assertWishClosed(openWishId, bob, expectedEthAmount, bobBalanceBefore, responseId);
    }

    function test_CloseWishTargetedWish() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, targetedWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(targetedWishId, "responseTxId");

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(targetedWishId, expectedTokenAmount);

        vm.expectEmit(true, true, true, true);
        emit CloseWish(targetedWishId, bob, responseId, expectedTokenAmount, expectedEthAmount);

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        wishpool.closeWish(targetedWishId, responseId);

        _assertWishClosed(targetedWishId, bob, expectedEthAmount, bobBalanceBefore, responseId);
    }

    function test_CloseWishWithNoFunds() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        wishpool.closeWish(openWishId, responseId);

        (,, bool isOpen) = wishpool.wishes(openWishId);
        assertFalse(isOpen);
        (,, bool isRewarded) = wishpool.responses(responseId);
        assertTrue(isRewarded);
        assertEq(bob.balance, bobBalanceBefore, "Bob's balance should not change when there are no funds");
    }

    function testFail_CloseWishOpenWishUnauthorized() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.prank(charlie);
        wishpool.closeWish(openWishId, responseId);
    }

    function testFail_CloseWishTargetedWishUnauthorized() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(targetedWishId, "responseTxId");

        vm.prank(charlie);
        wishpool.closeWish(targetedWishId, responseId);
    }

    function testFail_CloseWishNonExistentWish() public {
        vm.prank(alice);
        wishpool.closeWish(999, 0);
    }

    function testFail_CloseWishWithoutResponse() public {
        vm.prank(alice);
        wishpool.closeWish(openWishId, 999);
    }

    function testFail_CloseWishWithUnsubmittedResponse() public {
        vm.prank(alice);
        wishpool.closeWish(openWishId, 0);
    }

    function testFail_CloseWishAlreadyClosedWish() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.startPrank(alice);
        wishpool.closeWish(openWishId, responseId);
        wishpool.closeWish(openWishId, responseId);
        vm.stopPrank();
    }

    // ==================== Helper Functions ====================

    function _createTestWishes() internal returns (uint256, uint256) {
        vm.startPrank(alice);
        
        // Create a dummy wish to ensure openWishId is not 0
        wishpool.createWish("dummyWishTxId", address(0));
        
        uint256 _openWishId = bodhi.assetIndex();
        wishpool.createWish("openWishTxId", address(0));

        uint256 _targetedWishId = bodhi.assetIndex();
        wishpool.createWish("targetedWishTxId", bob);
        vm.stopPrank();
        return (_openWishId, _targetedWishId);
    }

    function _addFundsToWish(address funder, uint256 wishId, uint256 fundAmount) internal {
        vm.startPrank(funder);
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(wishId, fundAmount);
        bodhi.buy{value: buyPrice}(wishId, fundAmount);
        bodhi.safeTransferFrom(funder, address(wishpool), wishId, fundAmount, "");
        vm.stopPrank();
    }

    function _assertWishClosed(uint256 wishId, address solver, uint256 expectedEthAmount, uint256 solverBalanceBefore, uint256 expectedResponseId) internal view {
        (,, bool isOpen) = wishpool.wishes(wishId);
        assertFalse(isOpen, "Wish should be marked as closed");
        (,, bool isRewarded) = wishpool.responses(expectedResponseId);
        assertTrue(isRewarded, "Response should be marked as rewarded");
        assertEq(solver.balance, solverBalanceBefore + expectedEthAmount, "Solver should receive the expected ETH amount");
    }
}
