// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// new wishpool with solution submit process

contract Wishpool2 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Pool {
        address creator;
        address solver;
        bool completed;
    }

    struct Solution {
        string arTxId;
        address solver;
    }

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => Solution[]) public solutions;

    event Create(uint256 indexed poolId, address indexed creator, address indexed solver);
    event SubmitSolution(uint256 indexed poolId, address indexed solver, string arTxId);
    event Complete(uint256 indexed poolId, address indexed solver, uint256 amount); // TODO change

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

    function submitSolution(uint256 poolId, string calldata arTxId) external {
        Pool memory pool = pools[poolId];
        require(!pool.completed, "Pool already completed");

        if (pool.solver != address(0)) {
            require(msg.sender == pool.solver, "Only designated solver can submit");
        }

        solutions[poolId].push(Solution(arTxId, msg.sender));
        emit SubmitSolution(poolId, msg.sender, arTxId);
    }

    function complete(uint256 poolId, uint256 solutionIndex) external {
        Pool memory pool = pools[poolId];
        require(!pool.completed, "Pool already completed");
        require(solutionIndex < solutions[poolId].length, "Invalid solution index");
        require(
            (pool.solver == address(0) && msg.sender == pool.creator)
                || (pool.solver != address(0) && msg.sender == pool.solver),
            "Unauthorized"
        );

        Solution memory solution = solutions[poolId][solutionIndex];
        if (pool.solver == address(0)) {
            pool.solver = solution.solver;
        } else {
            require(solution.solver == pool.solver, "Chosen solution must be from designated solver");
        }
        pools[poolId].completed = true;

        uint256 balance = BODHI.balanceOf(address(this), poolId);
        emit Complete(poolId, pool.solver, balance);
        if (balance > 0) {
            BODHI.safeTransferFrom(address(this), pool.solver, poolId, balance, "");
        }
    }

    receive() external payable {}
}
