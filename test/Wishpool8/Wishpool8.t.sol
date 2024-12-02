// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool8.sol";
import {Bodhi} from "../../src/Bodhi.sol";
import {ERC1155TokenReceiver} from "../../src/peripheral/ERC1155TokenReceiver.sol";

/// @notice Test contract to attempt reentrancy attacks
contract ReentrancyAttacker is ERC1155TokenReceiver {
    Wishpool8 private wishpool;
    uint256 private wishId;
    uint256 private attackCount;

    constructor(Wishpool8 _wishpool, uint256 _wishId) {
        wishpool = _wishpool;
        wishId = _wishId;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public override returns (bytes4) {
        if (attackCount == 0) {
            attackCount++;
            wishpool.createWishAndBuy{value: 1 ether}("attackTxId", address(this), 1 ether);
        }
        return this.onERC1155Received.selector;
    }

    receive() external payable {
        if (attackCount == 0) {
            attackCount++;
            wishpool.submitAndReward(wishId, "attackTxId", 0);
        }
    }
}

/// @notice Test suite for Wishpool8 contract
contract Wishpool8Test is Test, ERC1155TokenReceiver {
    Wishpool8 public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    string arTxId = "testArTxId";

    uint256 public openWishId;
    uint256 public targetedWishId;
    uint256 public constant INITIAL_BALANCE = 100 ether;

    event CreateWish(uint256 indexed wishId, address indexed creator, address indexed solver);
    event Submit(uint256 indexed wishId, address indexed creator, uint256 submissionId);
    event Reward(
        uint256 indexed wishId,
        address indexed to,
        uint256 indexed submissionId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool8(address(bodhi));
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

    /// @notice Verify anyone can submit to an open wish
    function test_SubmitToOpenWish() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit Submit(openWishId, bob, submissionId);
        
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        (address creator, uint256 wishId, bool isRewarded) = wishpool.submissions(submissionId);
        assertEq(creator, bob);
        assertEq(wishId, openWishId);
        assertFalse(isRewarded);
    }

    /// @notice Verify only designated solver can submit to targeted wish
    function test_SubmitToTargetedWish() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.expectEmit(true, true, true, true);
        emit Submit(targetedWishId, bob, submissionId);
        
        vm.prank(bob);
        wishpool.submit(targetedWishId, "submissionTxId");

        (address creator, uint256 wishId, bool isRewarded) = wishpool.submissions(submissionId);
        assertEq(creator, bob);
        assertEq(wishId, targetedWishId);
        assertFalse(isRewarded);
    }

    /// @notice Verify unauthorized users cannot submit to targeted wish
    function testFail_SubmitToTargetedWishUnauthorized() public {
        vm.prank(charlie);
        wishpool.submit(targetedWishId, "submissionTxId");
    }

    /// @notice Verify submissions to non-existent wishes are rejected
    function testFail_SubmitToNonExistentWish() public {
        uint256 nonExistentWishId = 9999;
        vm.prank(bob);
        wishpool.submit(nonExistentWishId, "submissionTxId");
    }

    // ==================== Reward Tests ====================

    /// @notice Verify basic reward functionality
    function test_RewardSubmission() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 expectedTokenAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, expectedTokenAmount);
        uint256 bobBalanceBefore = bob.balance;

        vm.expectEmit(true, true, true, true);
        emit Reward(openWishId, bob, submissionId, expectedTokenAmount, expectedEthAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, 0);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify multiple responses can be rewarded for same wish
    function test_RewardMultipleSubmissions() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // Setup responses
        uint256 submissionId1 = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId1");

        uint256 submissionId2 = bodhi.assetIndex();
        vm.prank(charlie);
        wishpool.submit(openWishId, "submissionTxId2");

        uint256 rewardAmount = 1 ether;
        uint256 bobBalanceBefore = bob.balance;
        uint256 charlieBalanceBefore = charlie.balance;

        // First reward
        vm.startPrank(alice);
        uint256 expectedEthAmount1 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, submissionId1, rewardAmount);
        
        // Second reward - recalculate price due to pool changes
        uint256 expectedEthAmount2 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, submissionId2, rewardAmount);
        vm.stopPrank();

        // Verify both rewards
        _assertSubmissionRewarded(submissionId1, bob, expectedEthAmount1, bobBalanceBefore);
        _assertSubmissionRewarded(submissionId2, charlie, expectedEthAmount2, charlieBalanceBefore);
    }

    /// @notice Verify rewards with specific token amount
    function test_RewardWithSpecificAmount() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 specifiedAmount = 0.5 ether;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, specifiedAmount);
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, specifiedAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    // ==================== Security Tests ====================

    /// @notice Verify auto-calculation of reward amount when amount is zero
    function test_RewardWithZeroAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedAmount = fundAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, expectedAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, 0);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify excessive reward amounts are rejected
    function test_RewardWithExcessiveAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        vm.prank(alice);
        vm.expectRevert();
        wishpool.reward(openWishId, submissionId, 2 ether);
    }

    /// @notice Verify rewards work correctly after direct token transfers
    function test_RewardAfterTokenTransfer() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);
        
        // Additional direct token transfer
        uint256 extraAmount = 0.5 ether;
        _addFundsToWish(charlie, openWishId, extraAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 totalAmount = fundAmount + extraAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, totalAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, 0);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify a submission cannot be rewarded twice
    function testFail_RewardSubmissionTwice() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        vm.startPrank(alice);
        wishpool.reward(openWishId, submissionId, 0);
        wishpool.reward(openWishId, submissionId, 0);
        vm.stopPrank();
    }

    /// @notice Verify only authorized users can reward submissions
    function testFail_RewardUnauthorized() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        vm.prank(charlie);
        wishpool.reward(openWishId, submissionId, 0);
    }

    /// @notice Verify invalid submission IDs are rejected
    function testFail_RewardInvalidSubmission() public {
        vm.prank(alice);
        wishpool.reward(openWishId, 999, 0);
    }

    /// @notice Verify minimum reward amount (1 wei) works correctly
    function test_RewardWithMinimumAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 minAmount = 1; // 1 wei
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, minAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, minAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify rewards work correctly after market price changes
    function test_RewardAfterMarketPriceChange() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // Simulate market activity to change price
        _simulateMarketActivity(openWishId);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 rewardAmount = 0.5 ether;
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, rewardAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Verify correct handling of multiple token types
    function test_RewardWithMultipleTokenTypes() public {
        uint256 fundAmount = 1 ether;
        uint256 premintAmount = 1 ether; // Creator premint amount
        
        _addFundsToWish(alice, openWishId, fundAmount);
        uint256 otherWishId = _createOtherWish();
        _addFundsToWish(alice, otherWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 totalAmount = fundAmount + premintAmount;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, totalAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, 0); // Use 0 to reward all available tokens

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
        
        assertEq(
            bodhi.balanceOf(address(wishpool), otherWishId), 
            fundAmount + premintAmount,
            "Other wish token balance should include premint amount"
        );
    }

    // ==================== New Function Tests ====================

    /// @notice Test createWishAndBuy with token purchase
    function test_CreateWishAndBuy() public {
        uint256 wishId = bodhi.assetIndex();
        uint256 amount = 1 ether;
        uint256 price = _getInitialBuyPrice(amount);
        
        vm.expectEmit(true, true, true, true);
        emit CreateWish(wishId, alice, bob);
        
        vm.prank(alice);
        wishpool.createWishAndBuy{value: price}("newWishTxId", bob, amount);

        // Verify wish creation
        (address creator, address solver) = wishpool.wishes(wishId);
        assertEq(creator, alice);
        assertEq(solver, bob);

        // Verify token purchase
        assertEq(bodhi.balanceOf(alice, wishId), amount);
    }

    /// @notice Test createWishAndBuy without token purchase
    function test_CreateWishAndBuyNoTokens() public {
        uint256 wishId = bodhi.assetIndex();
        
        vm.prank(alice);
        wishpool.createWishAndBuy{value: 0}("newWishTxId", bob, 0);

        (address creator, address solver) = wishpool.wishes(wishId);
        assertEq(creator, alice);
        assertEq(solver, bob);
        assertEq(bodhi.balanceOf(alice, wishId), 0);
    }

    /// @notice Test createWishAndBuy with incorrect payment amount
    function testFail_CreateWishAndBuyInvalidPayment() public {
        uint256 amount = 1 ether;
        uint256 price = bodhi.getBuyPriceAfterFee(0, amount);
        
        vm.prank(alice);
        wishpool.createWishAndBuy{value: price + 1}("newWishTxId", bob, amount);
    }

    /// @notice Test submitAndReward basic flow
    function test_SubmitAndReward() public {
        // Create wish with bob as solver
        vm.prank(alice);
        wishpool.createWish("newWishTxId", bob);
        uint256 wishId = bodhi.assetIndex() - 1;

        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, wishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(wishId, fundAmount);

        vm.expectEmit(true, true, true, true);
        emit Submit(wishId, bob, submissionId);
        vm.expectEmit(true, true, true, true);
        emit Reward(wishId, bob, submissionId, fundAmount, expectedEthAmount);

        vm.prank(bob);
        wishpool.submitAndReward(wishId, "submissionTxId", 0);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Test submitAndReward with specific amount
    function test_SubmitAndRewardSpecificAmount() public {
        uint256 fundAmount = 2 ether;
        // Create wish with bob as solver
        vm.prank(alice);
        wishpool.createWish("newWishTxId", bob);
        uint256 wishId = bodhi.assetIndex() - 1;
        _addFundsToWish(alice, wishId, fundAmount);

        uint256 rewardAmount = 1 ether;
        uint256 submissionId = bodhi.assetIndex();
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(wishId, rewardAmount);

        vm.prank(bob);
        wishpool.submitAndReward(wishId, "submissionTxId", rewardAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    // ==================== Reentrancy Tests ====================

    /// @notice Test reentrancy protection in createWishAndBuy
    function test_CreateWishAndBuyReentrancyProtection() public {
        uint256 wishId = bodhi.assetIndex();
        uint256 amount = 1 ether;
        uint256 price = bodhi.getBuyPriceAfterFee(wishId, amount);
        
        ReentrancyAttacker attacker = new ReentrancyAttacker(wishpool, wishId);
        
        vm.expectRevert();
        vm.prank(address(attacker));
        wishpool.createWishAndBuy{value: price}("attackTxId", address(attacker), amount);
    }

    /// @notice Test reentrancy protection in submitAndReward
    function test_SubmitAndRewardReentrancyProtection() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);
        
        ReentrancyAttacker attacker = new ReentrancyAttacker(wishpool, openWishId);
        
        vm.expectRevert();
        vm.prank(address(attacker));
        wishpool.submitAndReward(openWishId, "attackTxId", 0);
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
    function _assertSubmissionRewarded(
        uint256 submissionId,
        address solver,
        uint256 expectedEthAmount,
        uint256 solverBalanceBefore
    ) internal view {
        (,, bool isRewarded) = wishpool.submissions(submissionId);
        assertTrue(isRewarded, "Submission should be marked as rewarded");
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

    /// @notice Calculate initial buy price for a new wish (starting from CREATOR_PREMINT)
    /// @param amount Amount of tokens to buy
    /// @return price Total price including creator fee
    function _getInitialBuyPrice(uint256 amount) internal view returns (uint256) {
        uint256 basePrice = bodhi.getPrice(1 ether, amount);
        uint256 creatorFee = (basePrice * 0.05 ether) / 1 ether;
        return basePrice + creatorFee;
    }
}