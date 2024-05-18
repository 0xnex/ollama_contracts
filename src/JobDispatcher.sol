// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract JobDispatcher {
    mapping(bytes32 => bool) public withdraweds;
    address public prover;

    event JobCompleted(uint256 indexed jobId, uint256 indexed nodeId, uint256 points);

    error zero_address();
    error invalid_prover();
    error already_withdraw(bytes32 hash);

    constructor(address _prover) {
        if (_prover == address(0)) {
            revert zero_address();
        }
        prover = _prover;
    }

    function completeJob(
        uint256 category,
        uint256 jobId,
        uint256 nodeId,
        uint256 role,
        uint256 points,
        bytes calldata signature
    ) external {
        bytes32 hash =
            MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked(category, jobId, nodeId, role, points)));
        if (!SignatureChecker.isValidSignatureNow(prover, hash, signature)) {
            revert invalid_prover();
        }

        if (withdraweds[hash]) {
            revert already_withdraw(hash);
        }

        withdraweds[hash] = true;
        emit JobCompleted(jobId, nodeId, points);
    }
}
