// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

error InvalidWish();
error Unauthorized();
error InvalidResponse();
error EtherTransferFailed();

contract Wishpool7 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Wish {
        address creator;
        address solver;    // Optional designated solver
    }

    struct Response {
        address creator;
        uint256 wishId;
        bool isRewarded;
    }

    mapping(uint256 => Wish) public wishes;
    mapping(uint256 => Response) public responses;

    event CreateWish(uint256 indexed wishId, address indexed creator, address indexed solver);
    event CreateResponse(uint256 indexed wishId, address indexed solver, uint256 responseId);
    event Reward(
        uint256 indexed wishId,
        address indexed solver,
        uint256 indexed responseId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    constructor(address _bodhi) {
        BODHI = IBodhi(_bodhi);
    }

    function createWish(string calldata arTxId, address solver) external {
        uint256 wishId = BODHI.assetIndex();
        wishes[wishId] = Wish(msg.sender, solver);
        emit CreateWish(wishId, msg.sender, solver);
        BODHI.create(arTxId);
    }

    function createResponse(uint256 wishId, string calldata arTxId) external {
        Wish memory wish = wishes[wishId];
        if (wish.creator == address(0)) revert InvalidWish();
        if (wish.solver != address(0) && msg.sender != wish.solver) revert Unauthorized();

        uint256 responseId = BODHI.assetIndex();
        responses[responseId] = Response(msg.sender, wishId, false);
        
        emit CreateResponse(wishId, msg.sender, responseId);
        BODHI.create(arTxId);
    }

    function reward(uint256 wishId, uint256 responseId, uint256 amount) external {
        Wish memory wish = wishes[wishId];
        if (msg.sender != wish.creator && msg.sender != wish.solver) revert Unauthorized();

        Response storage response = responses[responseId];
        if (response.creator == address(0) || response.wishId != wishId) revert InvalidResponse();
        if (wish.solver != address(0) && response.creator != wish.solver) revert Unauthorized();
        if (response.isRewarded) revert InvalidResponse();

        response.isRewarded = true;

        uint256 balance = BODHI.balanceOf(address(this), wishId);
        uint256 supply = BODHI.totalSupply(wishId);
        uint256 rewardAmount = amount == 0 ? 
            (balance + 1 ether > supply ? supply - 1 ether : balance) : 
            amount;
            
        uint256 sellPrice = BODHI.getSellPriceAfterFee(wishId, rewardAmount);

        emit Reward(wishId, response.creator, responseId, rewardAmount, sellPrice);
        
        if (rewardAmount > 0) {
            BODHI.sell(wishId, rewardAmount);
            (bool sent,) = response.creator.call{value: sellPrice}("");
            if (!sent) revert EtherTransferFailed();
        }
    }

    receive() external payable {}
}
