// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./WishpoolBase.t.sol";

contract WishpoolTradeTest is WishpoolBaseTest {
    uint256 public poolId;
    uint256 public constant INITIAL_BALANCE = 100 ether;

    event Trade(
        Bodhi.TradeType indexed tradeType,
        uint256 indexed assetId,
        address indexed sender,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 creatorFee
    );

    function setUp() public override {
        super.setUp();

        // Create a pool for testing
        vm.startPrank(alice);
        poolId = bodhi.assetIndex();
        wishpool.createPool("testArTxId", address(0)); // Regular pool
        vm.stopPrank();
    }

    function test_Buy() public {
        vm.startPrank(bob);
        uint256 amount = 1 ether;
        uint256 price = bodhi.getBuyPriceAfterFee(poolId, amount);

        vm.expectEmit(true, true, true, false);
        emit Trade(Bodhi.TradeType.Buy, poolId, address(bob), amount, 0, 0);
        bodhi.buy{value: price}(poolId, amount);

        assertEq(bodhi.balanceOf(bob, poolId), amount, "Bob should have received the tokens");
        assertEq(bob.balance, INITIAL_BALANCE - price, "Bob's balance should be reduced by the price");
        vm.stopPrank();
    }

    function test_Sell() public {
        // buy shares
        vm.startPrank(bob);
        uint256 buyPrice = bodhi.getBuyPriceAfterFee(poolId, 1 ether);
        bodhi.buy{value: buyPrice}(poolId, 1 ether);

        // sell shares
        uint256 sellAmount = 0.5 ether;
        uint256 sellPrice = bodhi.getSellPriceAfterFee(poolId, sellAmount);
        uint256 balanceBeforeSell = bob.balance;

        vm.expectEmit(true, true, true, false);
        emit Trade(Bodhi.TradeType.Sell, poolId, address(bob), sellAmount, 0, 0);
        bodhi.sell(poolId, sellAmount);

        assertEq(bodhi.balanceOf(bob, poolId), 0.5 ether, "Bob should have 0.5 tokens left");
        assertEq(bob.balance, balanceBeforeSell + sellPrice, "Bob's balance should be increased by the sell price");
        vm.stopPrank();
    }

    function test_AddFund() public {
        vm.startPrank(bob);
        uint256 buyAmount = 1 ether;
        bodhi.buy{value: bodhi.getBuyPriceAfterFee(poolId, buyAmount)}(poolId, buyAmount);

        uint256 donateAmount = buyAmount / 2;
        uint256 wishpoolInitialBalance = bodhi.balanceOf(address(wishpool), poolId);

        // bob donates share to the pool
        bodhi.safeTransferFrom(bob, address(wishpool), poolId, donateAmount, "");

        assertEq(
            bodhi.balanceOf(bob, poolId),
            buyAmount - donateAmount,
            "Bob's balance should decrease by the donated amount"
        );
        assertEq(
            bodhi.balanceOf(address(wishpool), poolId),
            wishpoolInitialBalance + donateAmount,
            "Wishpool's balance should increase by the donated amount"
        );
        vm.stopPrank();
    }
}
