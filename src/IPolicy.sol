// SPDX-License-Identifier: MIT

pragma solidity =0.8.25;

interface IPolicy {
    struct Profile {
        uint96 syncedPoints;
        uint96 points;
        uint64 models; // can sava 32 models. every model has 2 bits, 1st bit represents if this models is purchased and 2nd represents this verification node is purchased.
    }

    function getPointsForNextModel(Profile memory profile) external returns (uint64);
    function getEthsForNextVerificationNode(Profile memory profile) external returns (uint256);
    function getWithdrawRatio(Profile memory profile) external returns (uint64);
}
