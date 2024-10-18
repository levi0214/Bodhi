// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// Changelog: Wishpool5 to Wishpool6

// 1. Terminology Changes:
//    - 'Mission' renamed to 'Wish'
//    - 'Submission' renamed to 'Response'

// 2. Function, Event, and Interface Renaming:
//    - CreateMission event -> CreateWish
//    - CreateSubmission event -> CreateResponse
//    - CompleteMission event -> CloseWish
//    - createMission function -> createWish
//    - createSubmission function -> createResponse
//    - completeMission function -> closeWish
//    - missions mapping -> wishes mapping
//    - submissionToCreator mapping -> responses mapping

// 3. Struct Updates:
//    - Wish struct (formerly Mission):
//      - Removed 'completed' field
//      - Added 'isOpen' field
//      - Removed 'submission' field
//    - Added new Response struct

// 4. Error Handling:
//    - Updated error names to reflect new terminology

// 5. Removed redundant mapping:
//    - Removed responseToWish mapping as Response struct contains wishId

error InvalidWish();
error Unauthorized();
error InvalidResponse();
error EtherTransferFailed();

contract Wishpool6 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Wish {
        address creator;
        address solver;
        bool isOpen;
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
    event CloseWish(
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
        wishes[wishId] = Wish(msg.sender, solver, true);
        emit CreateWish(wishId, msg.sender, solver);
        BODHI.create(arTxId);
    }

    function createResponse(uint256 wishId, string calldata arTxId) external {
        Wish memory wish = wishes[wishId];
        if (!wish.isOpen || wish.creator == address(0)) revert InvalidWish();
        if (wish.solver != address(0) && msg.sender != wish.solver) revert Unauthorized();

        uint256 responseId = BODHI.assetIndex();
        responses[responseId] = Response(msg.sender, wishId, false);
        
        emit CreateResponse(wishId, msg.sender, responseId);
        BODHI.create(arTxId);
    }

    function closeWish(uint256 wishId, uint256 responseId) external {
        Wish storage wish = wishes[wishId];
        if (!wish.isOpen) revert InvalidWish();
        if (msg.sender != wish.creator && msg.sender != wish.solver) revert Unauthorized();

        Response storage response = responses[responseId];
        if (response.creator == address(0) || response.wishId != wishId) revert InvalidResponse();
        if (wish.solver != address(0) && response.creator != wish.solver) revert Unauthorized();

        wish.isOpen = false;
        response.isRewarded = true;

        uint256 balance = BODHI.balanceOf(address(this), wishId);
        uint256 supply = BODHI.totalSupply(wishId);
        uint256 amount = balance + 1 ether > supply ? supply - 1 ether : balance;
        uint256 sellPrice = BODHI.getSellPriceAfterFee(wishId, amount);

        emit CloseWish(wishId, response.creator, responseId, amount, sellPrice);
        if (amount > 0) {
            BODHI.sell(wishId, amount);
            (bool sent,) = response.creator.call{value: sellPrice}("");
            if (!sent) revert EtherTransferFailed();
        }
    }

    receive() external payable {}
}
