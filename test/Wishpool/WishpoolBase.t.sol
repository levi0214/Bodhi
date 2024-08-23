// File: WishpoolBase.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/Wishpool/Wishpool.sol";
import "../../src/Bodhi.sol";
import "../../src/peripheral/ERC1155TokenReceiver.sol";

contract WishpoolBaseTest is Test, ERC1155TokenReceiver {
    Wishpool public wishpool;
    Bodhi public bodhi;
    address public alice = address(0x1);
    address public bob = address(0x2);
    string arTxId = "testArTxId";

    function setUp() public virtual {
        bodhi = new Bodhi();
        wishpool = new Wishpool(address(bodhi));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }
}
