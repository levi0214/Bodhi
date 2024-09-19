// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// From Wishpool3 to Wishpool4:
// - Replaced `solutions` array mapping with `solutionToPool` single mapping.
// - Modified `submitSolution`: now maps solution to pool instead of storing in array.
// - Updated `complete`: checks solution belongs to pool using new mapping.
// - Removed `getSolutions` function.
// - Added share selling to `complete` function
// - Modified `Complete` event to include tokenAmount sold and ethAmount sent to solver

contract Wishpool4 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Pool {
        address creator;
        address solver;
        bool completed;
    }

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => uint256) public solutionToPool;

    event Create(uint256 indexed poolId, address indexed creator, address indexed solver);
    event SubmitSolution(uint256 indexed poolId, address indexed solver, uint256 solutionId);
    event Complete(
        uint256 indexed poolId,
        address indexed solver,
        uint256 indexed solutionId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    constructor(address _bodhi) {
        BODHI = IBodhi(_bodhi);
    }

    // regular pool: createPool('', address(0))
    // special pool: createPool('', 0x...)
    function createPool(string calldata arTxId, address solver) external {
        uint256 poolId = BODHI.assetIndex();
        pools[poolId] = Pool(msg.sender, solver, false);
        emit Create(poolId, msg.sender, solver);
        BODHI.create(arTxId);
    }

    function submitSolution(uint256 poolId, uint256 solutionId) external {
        Pool storage pool = pools[poolId];
        require(!pool.completed, "Pool already completed");

        (,, address solutionCreator) = BODHI.assets(solutionId);
        require(solutionCreator != address(0) && msg.sender == solutionCreator, "Invalid solution");
        require(pool.solver == address(0) || solutionCreator == pool.solver, "Unauthorized");

        solutionToPool[solutionId] = poolId;
        emit SubmitSolution(poolId, msg.sender, solutionId);
    }

    function complete(uint256 poolId, uint256 solutionId) external {
        Pool storage pool = pools[poolId];
        require(!pool.completed, "Pool already completed");
        require(msg.sender == pool.creator || msg.sender == pool.solver, "Unauthorized");

        (,, address solutionCreator) = BODHI.assets(solutionId);
        require(solutionCreator != address(0) && solutionToPool[solutionId] == poolId, "Invalid solution");

        if (pool.solver == address(0)) {
            pool.solver = solutionCreator;
        } else {
            require(solutionCreator == pool.solver, "Solution must be from designated solver");
        }

        pool.completed = true;

        uint256 balance = BODHI.balanceOf(address(this), poolId);
        uint256 supply = BODHI.totalSupply(poolId);
        uint256 amount = balance + 1 ether > supply ? supply - 1 ether : balance;
        uint256 sellPrice = BODHI.getSellPriceAfterFee(poolId, amount);

        emit Complete(poolId, pool.solver, solutionId, amount, sellPrice);
        if (amount > 0) {
            BODHI.sell(poolId, amount);
            (bool sent,) = pool.solver.call{value: sellPrice}("");
            require(sent, "Failed to send Ether");
        }
    }

    receive() external payable {}
}
