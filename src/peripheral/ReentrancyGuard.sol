// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

abstract contract ReentrancyGuard {
    uint256 private locked = 1;
    
    modifier nonReentrant() {
        require(locked == 1);
        locked = 2;
        _;
        locked = 1;
    }
} 