// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool7.sol";
import {Bodhi} from "../../src/Bodhi.sol";
import {ERC1155TokenReceiver} from "../../src/peripheral/ERC1155TokenReceiver.sol";

contract Wishpool7Test is Test, ERC1155TokenReceiver {
    Wishpool7 public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    string arTxId = "testArTxId";

    uint256 public openWishId;
    uint256 public targetedWishId;
    uint256 public constant INITIAL_BALANCE = 100 ether;

    event CreateWish(uint256 indexed wishId, address indexed creator, address indexed solver);
    event CreateResponse(uint256 indexed wishId, address indexed solver, uint256 responseId);
    event Reward(
        uint256 indexed wishId,
        address indexed solver,
        uint256 indexed responseId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool7(address(bodhi));
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

        (address creator, address solver) = wishpool.wishes(newWishId);
        assertEq(creator, alice);
        assertEq(solver, address(0));
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

    function testFail_CreateResponseTargetedWishUnauthorized() public {
        vm.prank(charlie);
        wishpool.createResponse(targetedWishId, "responseTxId");
    }

    function testFail_CreateResponseForNonExistentWish() public {
        uint256 nonExistentWishId = 9999;
        vm.prank(bob);
        wishpool.createResponse(nonExistentWishId, "responseTxId");
    }

    // ==================== Reward Tests ====================

    function test_RewardResponse() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, expectedTokenAmount);
        uint256 bobBalanceBefore = bob.balance;

        vm.expectEmit(true, true, true, true);
        emit Reward(openWishId, bob, responseId, expectedTokenAmount, expectedEthAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, 0);

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
    }

    function test_RewardMultipleResponses() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // Create two responses
        uint256 responseId1 = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId1");

        uint256 responseId2 = bodhi.assetIndex();
        vm.prank(charlie);
        wishpool.createResponse(openWishId, "responseTxId2");

        uint256 rewardAmount = 1 ether;
        
        // 记录初始余额
        uint256 bobBalanceBefore = bob.balance;
        uint256 charlieBalanceBefore = charlie.balance;

        vm.startPrank(alice);
        
        // 第一次奖励
        uint256 expectedEthAmount1 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, responseId1, rewardAmount);
        
        // 第二次奖励 - 需要重新计算预期金额，因为池子中的代币数量已经改变
        uint256 expectedEthAmount2 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, responseId2, rewardAmount);
        
        vm.stopPrank();

        // 分别验证两次奖励
        _assertResponseRewarded(responseId1, bob, expectedEthAmount1, bobBalanceBefore);
        _assertResponseRewarded(responseId2, charlie, expectedEthAmount2, charlieBalanceBefore);
    }

    function test_RewardWithSpecificAmount() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 specifiedAmount = 0.5 ether;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, specifiedAmount);
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, specifiedAmount);

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
    }

    function testFail_RewardResponseTwice() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.startPrank(alice);
        wishpool.reward(openWishId, responseId, 0);
        wishpool.reward(openWishId, responseId, 0);
        vm.stopPrank();
    }

    function testFail_RewardUnauthorized() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.prank(charlie);
        wishpool.reward(openWishId, responseId, 0);
    }

    function testFail_RewardInvalidResponse() public {
        vm.prank(alice);
        wishpool.reward(openWishId, 999, 0);
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

    function _assertResponseRewarded(
        uint256 responseId,
        address solver,
        uint256 expectedEthAmount,
        uint256 solverBalanceBefore
    ) internal view {
        (,, bool isRewarded) = wishpool.responses(responseId);
        assertTrue(isRewarded, "Response should be marked as rewarded");
        assertEq(
            solver.balance,
            solverBalanceBefore + expectedEthAmount,
            "Solver should receive the expected ETH amount"
        );
    }
}