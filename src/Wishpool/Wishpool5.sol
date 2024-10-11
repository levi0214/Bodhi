// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// From Wishpool4 to Wishpool5:
// - Renamed 'pool' to 'mission'
// - Renamed 'solution' to 'submission'
// - Updated all related variable names and function names accordingly
// - Renamed events and functions as per the latest request
    // - Renamed Create event to CreateMission
    // - Renamed SubmitSubmission event to CreateSubmission
    // - Renamed Complete event to CompleteMission
    // - Renamed submitSubmission function to createSubmission
    // - Renamed complete function to completeMission


contract Wishpool5 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Mission {
        address creator;
        address solver;
        bool completed;
    }

    mapping(uint256 => Mission) public missions;
    mapping(uint256 => uint256) public submissionToMission;

    event CreateMission(uint256 indexed missionId, address indexed creator, address indexed solver);
    event CreateSubmission(uint256 indexed missionId, address indexed solver, uint256 submissionId);
    event CompleteMission(
        uint256 indexed missionId,
        address indexed solver,
        uint256 indexed submissionId,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    constructor(address _bodhi) {
        BODHI = IBodhi(_bodhi);
    }

    // open mission: createMission('', address(0))
    // targeted mission: createMission('', 0x...)
    function createMission(string calldata arTxId, address solver) external {
        uint256 missionId = BODHI.assetIndex();
        missions[missionId] = Mission(msg.sender, solver, false);
        emit CreateMission(missionId, msg.sender, solver);
        BODHI.create(arTxId);
    }

    function createSubmission(uint256 missionId, uint256 submissionId) external {
        Mission storage mission = missions[missionId];
        require(!mission.completed, "Mission already completed");

        (,, address submissionCreator) = BODHI.assets(submissionId);
        require(submissionCreator != address(0) && msg.sender == submissionCreator, "Invalid submission");
        require(mission.solver == address(0) || submissionCreator == mission.solver, "Unauthorized");

        submissionToMission[submissionId] = missionId;
        emit CreateSubmission(missionId, msg.sender, submissionId);
    }

    function completeMission(uint256 missionId, uint256 submissionId) external {
        Mission storage mission = missions[missionId];
        require(!mission.completed, "Mission already completed");
        require(msg.sender == mission.creator || msg.sender == mission.solver, "Unauthorized");

        (,, address submissionCreator) = BODHI.assets(submissionId);
        require(submissionCreator != address(0) && submissionToMission[submissionId] == missionId, "Invalid submission");

        if (mission.solver == address(0)) {
            mission.solver = submissionCreator;
        } else {
            require(submissionCreator == mission.solver, "Submission must be from designated solver");
        }

        mission.completed = true;

        uint256 balance = BODHI.balanceOf(address(this), missionId);
        uint256 supply = BODHI.totalSupply(missionId);
        uint256 amount = balance + 1 ether > supply ? supply - 1 ether : balance;
        uint256 sellPrice = BODHI.getSellPriceAfterFee(missionId, amount);

        emit CompleteMission(missionId, mission.solver, submissionId, amount, sellPrice);
        if (amount > 0) {
            BODHI.sell(missionId, amount);
            (bool sent,) = mission.solver.call{value: sellPrice}("");
            require(sent, "Failed to send Ether");
        }
    }

    receive() external payable {}
}