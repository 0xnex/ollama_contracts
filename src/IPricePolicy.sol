// SPDX-License-Identifier: MIT
interface IPricePolicy {
    function getNetxLevelPoint(uint256 tokenId) external returns (uint64);
    function getNextModelPoint(uint256 tokenId) external returns (uint64);
    function getNextVerifierTokenCount(uint256 tokenId) external returns (uint64);
    function getWithdrawRatio(uint256 tokenId) external returns (uint64);
}
