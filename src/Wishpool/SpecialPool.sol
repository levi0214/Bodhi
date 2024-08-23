// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import "../interface/IBodhi.sol";

// --- DRAFT ----

// Regular Pool: anyone can solve
// Special Pool: only target address can solve

contract SpecialPool is ERC1155TokenReceiver {
    IBodhi public immutable bodhi;

    event Create(uint256 indexed bountyId, address indexed sender, address indexed receiver);
    event AddFund(uint256 indexed bountyId, address indexed sender, uint256 amount);
    event Complete(uint256 indexed bountyId, address indexed receiver, uint256 amount, uint256 ethAmount);

    struct BountyInfo {
        address receiver;
        bool completed;
        uint256 solutionId;
    }

    mapping(uint256 => BountyInfo) public bounties; // bountyId => BountyInfo

    constructor(address _bodhi) {
        bodhi = IBodhi(_bodhi);
    }

    // create a task for `receiver`
    function create(string calldata arTxId, address receiver) external {
        uint256 bountyId = bodhi.assetIndex();
        bodhi.create(arTxId);
        bounties[bountyId] = BountyInfo(receiver, false, 0);
        emit Create(bountyId, msg.sender, receiver);
    }

    function addFund(uint256 bountyId, uint256 amount) external payable {
        uint256 price = bodhi.getBuyPriceAfterFee(bountyId, amount);
        bodhi.buy{value: price}(bountyId, amount); // seems no need to check msg.value
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        emit AddFund(bountyId, msg.sender, amount);
    }

    // only `receiver` can call
    function complete(uint256 bountyId, uint256 assetId) external {
        BountyInfo storage bounty = bounties[bountyId];
        require(msg.sender == bounty.receiver, "Only receiver can complete the bounty");
        require(!bounty.completed, "Bounty already completed");

        (,, address assetCreator) = bodhi.assets(assetId);
        require(assetCreator == bounty.receiver, "Asset creator is not bounty receiver");

        bounty.completed = true;
        bounty.solutionId = assetId;

        uint256 balance = bodhi.balanceOf(address(this), bountyId);
        uint256 supply = bodhi.totalSupply(bountyId);
        uint256 amount = balance + 1 ether > supply ? supply - 1 ether : balance;
        uint256 sellPrice = bodhi.getSellPriceAfterFee(bountyId, amount);

        if (amount > 0) {
            bodhi.sell(bountyId, amount);
            (bool sent,) = assetCreator.call{value: sellPrice}("");
            require(sent, "Failed to send Ether");
        }
        emit Complete(bountyId, assetCreator, amount, sellPrice);
    }

    receive() external payable {}
}
