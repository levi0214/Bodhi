// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {ReentrancyGuard} from "../peripheral/ReentrancyGuard.sol";
import {IBodhi} from "../interface/IBodhi.sol";

error InvalidWish();
error Unauthorized();
error InvalidSubmission();
error EtherTransferFailed();
error InvalidAmount();

contract Wishpool8 is ERC1155TokenReceiver, ReentrancyGuard {
    IBodhi public immutable BODHI;
    address public immutable TREASURY;

    struct Wish {
        address creator;
        address solver; // Optional designated solver
    }

    struct Submission {
        address creator;
        uint256 wishId;
        bool isRewarded;
    }

    mapping(uint256 => Wish) public wishes;
    mapping(uint256 => Submission) public submissions;

    event CreateWish(uint256 indexed wishId, address indexed creator, address indexed solver);
    event Submit(uint256 indexed wishId, address indexed creator, uint256 submissionId);
    event Reward(
        uint256 indexed wishId, address indexed to, uint256 indexed submissionId, uint256 tokenAmount, uint256 ethAmount
    );

    constructor(address _bodhi, address _treasury) {
        BODHI = IBodhi(_bodhi);
        TREASURY = _treasury;
    }

    function createWish(string calldata arTxId, address solver) public returns (uint256 wishId) {
        wishId = BODHI.assetIndex();
        wishes[wishId] = Wish(msg.sender, solver);
        emit CreateWish(wishId, msg.sender, solver);
        BODHI.create(arTxId);
    }

    function submit(uint256 wishId, string calldata arTxId) public returns (uint256 submissionId) {
        Wish memory wish = wishes[wishId];
        if (wish.creator == address(0)) revert InvalidWish();
        if (wish.solver != address(0) && msg.sender != wish.solver) revert Unauthorized();

        submissionId = BODHI.assetIndex();
        submissions[submissionId] = Submission(msg.sender, wishId, false);

        emit Submit(wishId, msg.sender, submissionId);
        BODHI.create(arTxId);
    }

    function reward(uint256 wishId, uint256 submissionId, uint256 amount) public {
        Wish memory wish = wishes[wishId];
        if (msg.sender != wish.creator && msg.sender != wish.solver) revert Unauthorized();

        Submission storage submission = submissions[submissionId];
        if (submission.creator == address(0) || submission.wishId != wishId) revert InvalidSubmission();
        if (wish.solver != address(0) && submission.creator != wish.solver) revert Unauthorized();
        if (submission.isRewarded) revert InvalidSubmission();

        submission.isRewarded = true;

        uint256 balance = BODHI.balanceOf(address(this), wishId);
        uint256 supply = BODHI.totalSupply(wishId);
        uint256 rewardAmount = amount == 0 ? (balance + 1 ether > supply ? supply - 1 ether : balance) : amount;

        uint256 sellPrice = BODHI.getSellPriceAfterFee(wishId, rewardAmount);

        emit Reward(wishId, submission.creator, submissionId, rewardAmount, sellPrice);

        if (rewardAmount > 0) {
            BODHI.sell(wishId, rewardAmount);
            (bool sent,) = submission.creator.call{value: sellPrice}("");
            if (!sent) revert EtherTransferFailed();
        }
    }

    function createWishAndBuy(string calldata arTxId, address solver, uint256 amount) external payable nonReentrant {
        uint256 wishId = createWish(arTxId, solver);

        if (amount > 0) {
            uint256 price = BODHI.getBuyPriceAfterFee(wishId, amount);
            require(msg.value == price, "Invalid payment");

            BODHI.buy{value: price}(wishId, amount);
            BODHI.safeTransferFrom(address(this), msg.sender, wishId, amount, "");
        }
    }

    function submitAndReward(uint256 wishId, string calldata arTxId, uint256 amount) external nonReentrant {
        uint256 submissionId = submit(wishId, arTxId);
        reward(wishId, submissionId, amount);
    }

    function withdraw() external {
        if (msg.sender != TREASURY) revert Unauthorized();
        (bool success,) = TREASURY.call{value: address(this).balance}("");
        if (!success) revert EtherTransferFailed();
    }

    receive() external payable {}
}
