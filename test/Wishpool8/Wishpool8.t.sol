// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool8.sol";
import {Bodhi} from "../../src/Bodhi.sol";
import {ERC1155TokenReceiver} from "../../src/peripheral/ERC1155TokenReceiver.sol";

/// @notice Contract for testing reentrancy attacks
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

contract Wishpool8Test is Test, ERC1155TokenReceiver {
    Wishpool8 public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint256 public openWishId;
    uint256 public targetedWishId;

    event CreateWish(uint256 indexed wishId, address indexed creator, address indexed solver);
    event Submit(uint256 indexed wishId, address indexed creator, uint256 submissionId);
    event Reward(
        uint256 indexed wishId,
        address indexed to,
        uint256 indexed submissionId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    // Base setup
    function setUp() public {
        bodhi = new Bodhi();
        wishpool = new Wishpool8(address(bodhi), address(this));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        
        // Setup test wishes
        vm.startPrank(alice);
        wishpool.createWish("openWishTxId", address(0));
        openWishId = bodhi.assetIndex() - 1;
        wishpool.createWish("targetedWishTxId", bob);
        targetedWishId = bodhi.assetIndex() - 1;
        vm.stopPrank();
    }

    // ============ Core Function Tests ============

    /// @notice Test wish creation
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

    /// @notice Test create and buy wish
    function test_CreateWishAndBuy() public {
        uint256 wishId = bodhi.assetIndex();
        uint256 amount = 1 ether;
        uint256 price = _getInitialBuyPrice(amount);
        
        vm.expectEmit(true, true, true, true);
        emit CreateWish(wishId, alice, bob);
        
        vm.prank(alice);
        wishpool.createWishAndBuy{value: price}("newWishTxId", bob, amount);

        (address creator, address solver) = wishpool.wishes(wishId);
        assertEq(creator, alice);
        assertEq(solver, bob);
        assertEq(bodhi.balanceOf(alice, wishId), amount);
    }

    /// @notice Test invalid payment amount
    function testFail_CreateWishAndBuyInvalidPayment() public {
        uint256 amount = 1 ether;
        uint256 price = bodhi.getBuyPriceAfterFee(0, amount);
        
        vm.prank(alice);
        wishpool.createWishAndBuy{value: price + 1}("newWishTxId", bob, amount);
    }

    // ============ Submission Tests ============

    /// @notice Test submitting to open wish
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

    /// @notice Test submitting to targeted wish
    function test_SubmitToTargetedWish() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(targetedWishId, "submissionTxId");

        (address creator, uint256 wishId, bool isRewarded) = wishpool.submissions(submissionId);
        assertEq(creator, bob);
        assertEq(wishId, targetedWishId);
        assertFalse(isRewarded);
    }

    /// @notice Test unauthorized submission
    function testFail_SubmitToTargetedWishUnauthorized() public {
        vm.prank(charlie);
        wishpool.submit(targetedWishId, "submissionTxId");
    }

    /// @notice Test submitting to nonexistent wish
    function testFail_SubmitToNonExistentWish() public {
        vm.prank(bob);
        wishpool.submit(999, "submissionTxId");
    }

    // ============ Reward Tests ============

    /// @notice Test basic reward functionality
    function test_RewardSubmission() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, fundAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, fundAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Test zero amount reward
    function test_RewardWithZeroAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, fundAmount + 1 ether);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, 0);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Test partial amount reward
    function test_RewardWithPartialAmount() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 partialAmount = 1 ether;
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, partialAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, partialAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
        assertEq(
            bodhi.balanceOf(address(wishpool), openWishId),
            fundAmount - partialAmount + 1 ether
        );
    }

    /// @notice Test double reward attempt
    function testFail_RewardSubmissionTwice() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        vm.startPrank(alice);
        wishpool.reward(openWishId, submissionId, 0);
        wishpool.reward(openWishId, submissionId, 0);
        vm.stopPrank();
    }

    /// @notice Test unauthorized reward
    function testFail_RewardUnauthorized() public {
        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        vm.prank(charlie);
        wishpool.reward(openWishId, submissionId, 0);
    }

    // ============ Security Tests ============

    /// @notice Test reentrancy protection
    function test_ReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(wishpool, openWishId);
        
        // Test createWishAndBuy reentrancy
        vm.expectRevert();
        vm.prank(address(attacker));
        wishpool.createWishAndBuy{value: 1 ether}("attackTxId", address(attacker), 1 ether);

        // Test submitAndReward reentrancy
        _addFundsToWish(alice, openWishId, 1 ether);
        vm.expectRevert();
        vm.prank(address(attacker));
        wishpool.submitAndReward(openWishId, "attackTxId", 0);
    }

    // ============ Complex Scenario Tests ============

    /// @notice Test multiple submissions and rewards
    function test_RewardMultipleSubmissions() public {
        uint256 fundAmount = 2 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // First submission
        uint256 submissionId1 = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId1");

        // Second submission
        uint256 submissionId2 = bodhi.assetIndex();
        vm.prank(charlie);
        wishpool.submit(openWishId, "submissionTxId2");

        uint256 rewardAmount = 1 ether;
        uint256 bobBalanceBefore = bob.balance;
        uint256 charlieBalanceBefore = charlie.balance;

        vm.startPrank(alice);
        // First reward
        uint256 expectedEthAmount1 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, submissionId1, rewardAmount);
        
        // Second reward
        uint256 expectedEthAmount2 = bodhi.getSellPriceAfterFee(openWishId, rewardAmount);
        wishpool.reward(openWishId, submissionId2, rewardAmount);
        vm.stopPrank();

        _assertSubmissionRewarded(submissionId1, bob, expectedEthAmount1, bobBalanceBefore);
        _assertSubmissionRewarded(submissionId2, charlie, expectedEthAmount2, charlieBalanceBefore);
    }

    /// @notice Test reward after price change
    function test_RewardAfterMarketPriceChange() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        // Simulate market activity to change price
        _simulateMarketActivity(openWishId);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(openWishId, fundAmount);

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, fundAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Test submit and reward in one tx
    function test_SubmitAndReward() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, targetedWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        uint256 bobBalanceBefore = bob.balance;
        uint256 expectedEthAmount = bodhi.getSellPriceAfterFee(targetedWishId, fundAmount);

        vm.expectEmit(true, true, true, true);
        emit Submit(targetedWishId, bob, submissionId);
        vm.expectEmit(true, true, true, true);
        emit Reward(targetedWishId, bob, submissionId, fundAmount, expectedEthAmount);

        vm.prank(bob);
        wishpool.submitAndReward(targetedWishId, "submissionTxId", fundAmount);

        _assertSubmissionRewarded(submissionId, bob, expectedEthAmount, bobBalanceBefore);
    }

    /// @notice Test unauthorized submit and reward
    function testFail_SubmitAndRewardUnauthorized() public {
        vm.prank(charlie);
        wishpool.submitAndReward(targetedWishId, "submissionTxId", 0);
    }

    // ============ Edge Case Tests ============

    /// @notice Test minimum reward amount
    function test_MinimumRewardAmount() public {
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

    /// @notice Test excessive reward amount
    function testFail_ExcessiveRewardAmount() public {
        uint256 fundAmount = 1 ether;
        _addFundsToWish(alice, openWishId, fundAmount);

        uint256 submissionId = bodhi.assetIndex();
        vm.prank(bob);
        wishpool.submit(openWishId, "submissionTxId");

        vm.prank(alice);
        wishpool.reward(openWishId, submissionId, 2 ether); // More than available
    }

    // ============ Withdraw Tests ============
    
    /// @notice Test basic withdrawal
    function test_Withdraw() public {
        vm.deal(address(wishpool), 1 ether);
        
        uint256 treasuryBalanceBefore = address(this).balance;
        uint256 contractBalanceBefore = address(wishpool).balance;
        
        wishpool.withdraw();
        
        assertEq(address(wishpool).balance, 0, "Contract should have 0 balance after withdraw");
        assertEq(
            address(this).balance,
            treasuryBalanceBefore + contractBalanceBefore,
            "Treasury should receive all funds"
        );
    }

    /// @notice Test unauthorized withdrawal
    function testFail_WithdrawUnauthorized() public {
        vm.deal(address(wishpool), 1 ether);
        
        vm.prank(alice);
        wishpool.withdraw();
    }

    /// @notice Test withdraw with zero balance
    function test_WithdrawZeroBalance() public {
        uint256 treasuryBalanceBefore = address(this).balance;
        
        wishpool.withdraw();
        
        assertEq(address(wishpool).balance, 0, "Contract balance should be 0");
        assertEq(
            address(this).balance,
            treasuryBalanceBefore,
            "Treasury balance should not change"
        );
    }

    /// @notice Test multiple withdrawals
    function test_MultipleWithdraws() public {
        // First withdrawal
        vm.deal(address(wishpool), 1 ether);
        wishpool.withdraw();
        assertEq(address(wishpool).balance, 0, "Contract should have 0 balance after first withdraw");
        
        // Second withdrawal with new funds
        vm.deal(address(wishpool), 0.5 ether);
        wishpool.withdraw();
        assertEq(address(wishpool).balance, 0, "Contract should have 0 balance after second withdraw");
    }

    /// @notice Test withdrawal after receiving creator fees
    function test_WithdrawAfterCreatorFees() public {
        // Setup: Create wish and simulate trading to generate creator fees
        uint256 wishId = bodhi.assetIndex();
        vm.prank(alice);
        wishpool.createWish("testWish", address(0));
        
        // Simulate trading to generate creator fees
        vm.startPrank(bob);
        uint256 tradeAmount = 1 ether;
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(wishId, tradeAmount);
        bodhi.buy{value: buyPrice}(wishId, tradeAmount);
        bodhi.sell(wishId, tradeAmount);
        vm.stopPrank();
        
        uint256 treasuryBalanceBefore = address(this).balance;
        uint256 contractBalance = address(wishpool).balance;
        require(contractBalance > 0, "Should have received creator fees");
        
        wishpool.withdraw();
        
        assertEq(address(wishpool).balance, 0, "Contract should have 0 balance after withdraw");
        assertEq(
            address(this).balance,
            treasuryBalanceBefore + contractBalance,
            "Treasury should receive all creator fees"
        );
    }

    // ============ Helper Functions ============

    /// @notice Add funds to a wish
    function _addFundsToWish(address funder, uint256 wishId, uint256 amount) internal {
        vm.prank(funder);
        uint256 price = bodhi.getBuyPriceAfterFee(wishId, amount);
        (bool success, ) = address(wishpool).call{value: price}("");
        require(success, "ETH transfer failed");
        
        vm.prank(address(wishpool));
        bodhi.buy{value: price}(wishId, amount);
    }

    /// @notice Verify reward results
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

    /// @notice Calculate initial buy price
    function _getInitialBuyPrice(uint256 amount) internal view returns (uint256) {
        uint256 basePrice = bodhi.getPrice(1 ether, amount);
        uint256 creatorFee = (basePrice * 0.05 ether) / 1 ether;
        return basePrice + creatorFee;
    }

    /// @notice Simulate market activity
    function _simulateMarketActivity(uint256 wishId) internal {
        vm.startPrank(charlie);
        uint256 tradeAmount = 0.1 ether;
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(wishId, tradeAmount);
        bodhi.buy{value: buyPrice}(wishId, tradeAmount);
        bodhi.sell(wishId, tradeAmount);
        vm.stopPrank();
    }

    // 添加 receive 函数以接收 ETH
    receive() external payable {}
}