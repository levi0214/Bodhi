// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool7.sol";
import {Bodhi} from "../../src/Bodhi.sol";
import {ERC1155TokenReceiver} from "../../src/peripheral/ERC1155TokenReceiver.sol";

/// @notice Test suite for Wishpool7 contract
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

    // ==================== Basic Function Tests ====================

    /// @notice Verify wish creation with correct creator and solver assignment
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

    /// @notice Verify anyone can respond to an open wish
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

    /// @notice Verify only designated solver can respond to targeted wish
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

    /// @notice Verify unauthorized users cannot respond to targeted wish
    function testFail_CreateResponseTargetedWishUnauthorized() public {
        vm.prank(charlie);
        wishpool.createResponse(targetedWishId, "responseTxId");
    }

    /// @notice Verify responses to non-existent wishes are rejected
    function testFail_CreateResponseForNonExistentWish() public {
        uint256 nonExistentWishId = 9999;
        vm.prank(bob);
        wishpool.createResponse(nonExistentWishId, "responseTxId");
    }

    // ==================== Reward Tests ====================

    /// @notice Verify basic reward functionality
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

    /// @notice Verify multiple responses can be rewarded for same wish
    function test_RewardMultipleResponses() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // Setup responses
        uint256 responseId1 = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId1");

        uint256 responseId2 = bodhi.assetIndex();
        vm.prank(charlie);
        wishpool.createResponse(openWishId, "responseTxId2");

        uint256 rewardAmount = 1 ether;
        uint256 bobBalanceBefore = bob.balance;
        uint256 charlieBalanceBefore = charlie.balance;

        // First reward
        vm.startPrank(alice);
        uint256 expectedEthAmount1 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, responseId1, rewardAmount);
        
        // Second reward - recalculate price due to pool changes
        uint256 expectedEthAmount2 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, responseId2, rewardAmount);
        vm.stopPrank();

        // Verify both rewards
        _assertResponseRewarded(responseId1, bob, expectedEthAmount1, bobBalanceBefore);
        _assertResponseRewarded(responseId2, charlie, expectedEthAmount2, charlieBalanceBefore);
    }

    /// @notice Verify rewards with specific token amount
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

    // ==================== Security Tests ====================

    /// @notice Verify auto-calculation of reward amount when amount is zero
    function test_RewardWithZeroAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, expectedAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, 0);

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify excessive reward amounts are rejected
    function test_RewardWithExcessiveAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.prank(alice);
        vm.expectRevert();
        wishpool.reward(openWishId, responseId, 2 ether);
    }

    /// @notice Verify rewards work correctly after direct token transfers
    function test_RewardAfterTokenTransfer() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);
        
        // Additional direct token transfer
        uint256 extraAmount = 0.5 ether;
        _addFundsToWish(charlie, openWishId, extraAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 totalAmount = fundAmount + extraAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, totalAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, 0);

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify a response cannot be rewarded twice
    function testFail_RewardResponseTwice() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.startPrank(alice);
        wishpool.reward(openWishId, responseId, 0);
        wishpool.reward(openWishId, responseId, 0);
        vm.stopPrank();
    }

    /// @notice Verify only authorized users can reward responses
    function testFail_RewardUnauthorized() public {
        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        vm.prank(charlie);
        wishpool.reward(openWishId, responseId, 0);
    }

    /// @notice Verify invalid response IDs are rejected
    function testFail_RewardInvalidResponse() public {
        vm.prank(alice);
        wishpool.reward(openWishId, 999, 0);
    }

    /// @notice Verify minimum reward amount (1 wei) works correctly
    function test_RewardWithMinimumAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 minAmount = 1; // 1 wei
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, minAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, minAmount);

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify rewards work correctly after market price changes
    function test_RewardAfterMarketPriceChange() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // Simulate market activity to change price
        _simulateMarketActivity(openWishId);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 rewardAmount = 0.5 ether;
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, rewardAmount);

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify correct handling of multiple token types
    function test_RewardWithMultipleTokenTypes() public {
        uint256 fundAmount = 1 ether;
        uint256 premintAmount = 1 ether; // Creator premint amount
        
        _addFundsToWish(alice, openWishId, fundAmount);
        uint256 otherWishId = _createOtherWish();
        _addFundsToWish(alice, otherWishId, fundAmount);

        uint256 responseId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.createResponse(openWishId, "responseTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 totalAmount = fundAmount + premintAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, totalAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, responseId, 0); // Use 0 to reward all available tokens

        _assertResponseRewarded(responseId, bob, expectedEthAmount, bobBalanceBefore);
        
        assertEq(
            bodhi.balanceOf(address(wishpool), otherWishId), 
            fundAmount + premintAmount,
            "Other wish token balance should include premint amount"
        );
    }

    // ==================== Helper Functions ====================

    /// @notice Creates test wishes for setup
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

    /// @notice Adds funds to a wish
    /// @param funder Address providing the funds
    /// @param wishId Target wish ID
    /// @param fundAmount Amount of tokens to fund
    function _addFundsToWish(address funder, uint256 wishId, uint256 fundAmount) internal {
        // Transfer ETH to wishpool
        vm.prank(funder);
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(wishId, fundAmount);
        (bool success, ) = address(wishpool).call{value: buyPrice}("");
        require(success, "ETH transfer failed");
        
        // Buy tokens directly from wishpool
        vm.prank(address(wishpool));
        bodhi.buy{value: buyPrice}(wishId, fundAmount);
    }

    /// @notice Verifies reward state and balances
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

    /// @notice Simulates market activity to change token price
    function _simulateMarketActivity(uint256 wishId) internal {
        // Simulate market activity by other users
        vm.startPrank(charlie);
        uint256 tradeAmount = 0.1 ether;
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(wishId, tradeAmount);
        bodhi.buy{value: buyPrice}(wishId, tradeAmount);
        bodhi.sell(wishId, tradeAmount);
        vm.stopPrank();
    }

    /// @notice Creates additional wish for multi-token tests
    function _createOtherWish() internal returns (uint256) {
        vm.prank(alice);
        wishpool.createWish("otherWishTxId", address(0));
        return bodhi.assetIndex() - 1;
    }
}