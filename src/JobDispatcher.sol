// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

contract JobDispatcher {
    mapping(bytes32 => bool) public withdraweds;

    event JobCompleted(
        uint256 indexed jobId,
        uint256 indexed nodeId,
        uint256 points
    );

    constructor() {}

    function completeJob(
        uint256 category,
        uint256 jobId,
        uint256 role,
        uint256 nodeId,
        bytes calldata signature
    ) external {
        bytes32 hash = keccak256(
            abi.encodePacked(category, jobId, role, nodeId)
        );
        require(withdraweds[hash] == false, "already withdrawed");
    }
}
