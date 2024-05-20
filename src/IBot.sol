// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface IBot is IERC721 {
    struct Profile {
        uint64 syncedPoints;
        uint64 points;
        uint8 level;
        uint120 models;
    }

    function getProfile(uint256 tokenId) external view returns (Profile memory);

    function balanceOfPoint(uint256 tokenId) external view returns (uint256);
}
