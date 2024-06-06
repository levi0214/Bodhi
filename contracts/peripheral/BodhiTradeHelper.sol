// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
import "../interface/IBodhi.sol";

contract BodhiTradeHelper is ERC1155TokenReceiver{
    event SafeBuy(uint256 indexed assetId, address indexed sender, uint256 tokenAmount, uint256 ethAmount);
    IBodhi public immutable bodhi;
    constructor(address _bodhi) {
        bodhi = IBodhi(_bodhi);
    }

    // Allow slippage
    function safeBuy(uint256 assetId, uint256 amount) external payable {
        uint256 price = bodhi.getBuyPriceAfterFee(assetId, amount);
        require(msg.value >= price, "Insufficient payment");
        emit SafeBuy(assetId, msg.sender, amount, price);
        bodhi.buy{value: price}(assetId, amount);
        bodhi.safeTransferFrom(address(this), msg.sender, assetId, amount, "");
        if (msg.value > price) {
            (bool refunded, ) = payable(msg.sender).call{value: msg.value - price}("");
            require(refunded, "Failed to refund excess payment");
        }
    }
}
