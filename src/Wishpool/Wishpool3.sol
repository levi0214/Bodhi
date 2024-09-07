// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// new wishpool with solution submit process

// 另一种方案的思考：
// 对 solution 的存储，可能不是绝对必要的，只是为了方便应用查询
// 后续可以考虑：
// 1. 移除 poolSolutions
// 2. submitSolution 减少权限检查，不存储，只发 event
// 3. 完全由 complete 函数检查权限
// 4. 在 UI 上进行用户友好的显示
// 5. * 或许可以添加 asset id => pool id 的 mapping，方便验证

contract Wishpool3 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Pool {
        address creator;
        address solver;
        bool completed;
    }

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => uint256[]) public poolSolutions;

    event Create(uint256 indexed poolId, address indexed creator, address indexed solver);
    event SubmitSolution(uint256 indexed poolId, address indexed solver, uint256 solutionId);
    event Complete(uint256 indexed poolId, address indexed solver, uint256 indexed solutionId, uint256 amount);

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
        require(solutionCreator != address(0), "Invalid solution");
        require(msg.sender == solutionCreator, "You are not the solution creator");
        require(pool.solver == address(0) || solutionCreator == pool.solver, "Unauthorized");

        poolSolutions[poolId].push(solutionId);
        emit SubmitSolution(poolId, msg.sender, solutionId);
    }

    function complete(uint256 poolId, uint256 solutionId) external {
        Pool storage pool = pools[poolId];
        require(!pool.completed, "Pool already completed");
        require(msg.sender == pool.creator || msg.sender == pool.solver, "Unauthorized");

        (,, address solutionCreator) = BODHI.assets(solutionId);
        require(solutionCreator != address(0), "Invalid solution");

        if (pool.solver == address(0)) {
            pool.solver = solutionCreator;
        } else {
            require(solutionCreator == pool.solver, "Solution must be from designated solver");
        }

        pool.completed = true;

        uint256 balance = BODHI.balanceOf(address(this), poolId);
        emit Complete(poolId, pool.solver, solutionId, balance);
        if (balance > 0) {
            BODHI.safeTransferFrom(address(this), pool.solver, poolId, balance, "");
        }
    }

    function getPoolSolutions(uint256 poolId) external view returns (uint256[] memory) {
        return poolSolutions[poolId];
    }

    receive() external payable {}
}
