// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import "../interface/IBodhi.sol";

// --- DRAFT ----

// Regular Pool: anyone can solve
// Special Pool: only target address can solve

contract RegularPool is ERC1155TokenReceiver {
    IBodhi public immutable bodhi;

    event Create(uint256 indexed bountyId, address indexed sender); // maybe `creator` `operator`
    event AddFund(uint256 indexed bountyId, address indexed sender, uint256 amount);     // no need, just watch "transfer" of bodhi
    event Complete(uint256 indexed bountyId, uint256 indexed assetId, address indexed worker, uint256 shareAmount, uint256 ethAmount);

    struct BountyInfo {
        address operator;   // does it need an operator since asset already has a creator? The only reason is that it can be set (for like reverse bounty)
        bool completed;
        uint256 solutionId;     // be careful when user assign solution to a post created by Space
    }

    mapping(uint256 => BountyInfo) public bounties; // bountyId => BountyInfo

    constructor(address _bodhi) {
        bodhi = IBodhi(_bodhi);  // use constant
    }
    
    // should it have a initial transfer? guess no
    function create(uint256 assetId) external {
        (,, address creator) = bodhi.assets(assetId);
        require(msg.sender == creator, "Only asset creator can create");
        require(bounties[assetId].operator == address(0), "Bounty already created");
        bounties[assetId] = BountyInfo(msg.sender, false, 0);
        emit Create(assetId, msg.sender);
    }

    function addFund(uint256 bountyId, uint256 amount) payable external {
        uint256 price = bodhi.getBuyPriceAfterFee(bountyId, amount);
        require(msg.value >= price, "Not enough fund");
        bodhi.buy{value: price}(bountyId, amount);
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        emit AddFund(bountyId, msg.sender, amount);
    }

    function complete(uint256 bountyId, uint256 assetId) external {
        BountyInfo storage bounty = bounties[bountyId];
        require(msg.sender == bounty.operator, "Only operator can complete the bounty");
        require(!bounty.completed, "Bounty already completed");

        (,,address assetCreator) = bodhi.assets(assetId);
        require(assetCreator != address(0), "Asset not exist");
        bounty.completed = true;
        bounty.solutionId = assetId;

        uint256 balance = bodhi.balanceOf(address(this), bountyId);
        uint256 supply = bodhi.totalSupply(bountyId);
        uint256 amount = balance + 1 ether > supply ? supply - 1 ether : balance;
        uint256 sellPrice = bodhi.getSellPriceAfterFee(bountyId, amount);
        
        if (amount > 0) {
            bodhi.sell(bountyId, amount);
            (bool sent, ) = assetCreator.call{value: sellPrice}("");
            require(sent, "Failed to send Ether");
        }
        emit Complete(bountyId, assetId, assetCreator, amount, sellPrice);  // "XXX completed the bounty, and received YYY ETH"
    }

    receive() external payable {}
}