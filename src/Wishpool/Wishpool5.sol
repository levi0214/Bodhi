// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC1155TokenReceiver} from "../peripheral/ERC1155TokenReceiver.sol";
import {IBodhi} from "../interface/IBodhi.sol";

// From Wishpool4 to Wishpool5:
// 1. Naming changes:
    // - Renamed 'pool' to 'mission'
    // - Renamed 'solution' to 'submission'
    // - Updated all related variable names and function names accordingly
    // - Renamed events and functions as per the latest request
        // - Renamed Create event to CreateMission
        // - Renamed SubmitSubmission event to CreateSubmission
        // - Renamed Complete event to CompleteMission
        // - Renamed submitSubmission function to createSubmission
        // - Renamed complete function to completeMission
// 2. submission changes:
    // - `createSubmission` now takes `arTxId` as argument, instead of `submissionId`
    // - add `submissionToCreator` mapping to track submission creators
// 3. replace `require` statements with `if` statements and `revert` statements
// 4. add error definitions outside the contract

// On Security:
// Note: 
//  - Since all assets are created by the contract, there's likely no risk from the Bodhi asset creator.
// TODO: 
//  - Check security risks when distributing rewards

error InvalidMission();
error Unauthorized();
error InvalidSubmission();
error EtherTransferFailed();

contract Wishpool5 is ERC1155TokenReceiver {
    IBodhi public immutable BODHI;

    struct Mission {
        address creator;
        address solver;
        bool completed;
        uint256 submission; // winning submission (do we really need to record this?)
    }

    mapping(uint256 => Mission) public missions;
    mapping(uint256 => uint256) public submissionToMission;
    mapping(uint256 => address) public submissionToCreator;

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
        missions[missionId] = Mission(msg.sender, solver, false, 0);
        emit CreateMission(missionId, msg.sender, solver);
        BODHI.create(arTxId);
    }

    function createSubmission(uint256 missionId, string calldata arTxId) external {
        Mission memory mission = missions[missionId];
        if (mission.completed || mission.creator == address(0)) revert InvalidMission();
        if (mission.solver != address(0) && msg.sender != mission.solver) revert Unauthorized();

        uint256 submissionId = BODHI.assetIndex();
        submissionToCreator[submissionId] = msg.sender;
        submissionToMission[submissionId] = missionId;
        
        emit CreateSubmission(missionId, msg.sender, submissionId);
        BODHI.create(arTxId);
    }

    function completeMission(uint256 missionId, uint256 submissionId) external {
        Mission storage mission = missions[missionId];
        if (mission.completed) revert InvalidMission();
        if (msg.sender != mission.creator && msg.sender != mission.solver) revert Unauthorized();

        address submissionCreator = submissionToCreator[submissionId];
        if (submissionCreator == address(0) || submissionToMission[submissionId] != missionId) revert InvalidSubmission();
        if (mission.solver != address(0) && submissionCreator != mission.solver) revert Unauthorized();

        mission.completed = true;
        mission.submission = submissionId;

        uint256 balance = BODHI.balanceOf(address(this), missionId);
        uint256 supply = BODHI.totalSupply(missionId);
        uint256 amount = balance + 1 ether > supply ? supply - 1 ether : balance;
        uint256 sellPrice = BODHI.getSellPriceAfterFee(missionId, amount);

        emit CompleteMission(missionId, submissionCreator, submissionId, amount, sellPrice);
        if (amount > 0) {
            BODHI.sell(missionId, amount);
            (bool sent,) = submissionCreator.call{value: sellPrice}("");
            if (!sent) revert EtherTransferFailed();
        }
    }

    receive() external payable {}
}