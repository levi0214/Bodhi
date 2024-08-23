// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// combined SpecialPool and RegularPool
contract Wishpool is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Pool {
        address creator;
        address solver;
        bool completed;
    }

    mapping(uint256 => Pool) public pools;

    event Create(uint256 indexed poolId, address indexed creator, address indexed solver);
    event Complete(uint256 indexed poolId, address indexed solver, uint256 amount);

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

    function complete(uint256 poolId, address solver) external {
        Pool memory pool = pools[poolId];
        require(!pool.completed, "Pool already completed");

        require(
            (pool.solver == address(0) && msg.sender == pool.creator)
                || (pool.solver != address(0) && msg.sender == pool.solver),
            "Unauthorized"
        );

        if (pool.solver == address(0)) pool.solver = solver;
        pools[poolId].completed = true;

        uint256 balance = BODHI.balanceOf(address(this), poolId);
        emit Complete(poolId, pool.solver, balance);
        if (balance > 0) {
            BODHI.safeTransferFrom(address(this), pool.solver, poolId, balance, "");
        }
    }

    receive() external payable {}
}

// TODO handle received fees
// TODO do we need to combine create & buy together?
// TODO do we need addFund function?
// TODO in complete, check totalSupply, don't sell below 1 supply
// TODO in complete, do we need `pools[poolId].solver = solver;`?
