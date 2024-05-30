// SPDX-License-Identifier: MIT

pragma solidity =0.8.25;

import "../lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

interface IBot {
    function ownerOf(uint256 tokenId) external view returns (address);
    function depositOllamaToken(uint256 tokenId, uint256 amount) external;
}

contract Incenstive {
    IERC20 public immutable ollamaToken;

    IBot public immutable bot;

    address public owner;

    // Duration of rewards to be paid out (in seconds)
    uint256 public duration;
    // Timestamp of when the rewards finish
    uint256 public finishAt;
    // Minimum of last updated time and reward finish time
    uint256 public updatedAt;
    // Reward to be paid out per second
    uint256 public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint256 public rewardPerTokenStored;
    // User tokenId => rewardPerTokenStored
    mapping(uint256 => uint256) public userRewardPerTokenPaid;
    // User tokenId => rewards to be claimed
    mapping(uint256 => uint256) public rewards;

    // Total staked
    uint256 public totalSupply;
    // User tokenId => staked amount
    mapping(uint256 => uint256) public balanceOf;
    // record used withdrawal request ids
    mapping(bytes32=>bool) public withrawalIds;

    event Staked(bytes32 indexed withrawalId, address indexed holder, uint256 indexed tokenId, uint256 amount);

    event Rewarded(address indexed holder, uint256 indexed tokenId, uint256 amount);

    constructor(IERC20 _ollamaToken, IBot _bot) {
        owner = msg.sender;
        ollamaToken = _ollamaToken;
        bot = _bot;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    modifier updateReward(address holder, uint256 tokenId) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (holder != address(0)) {
            require(bot.ownerOf(tokenId) == holder, "not owner");

            rewards[tokenId] = earned(tokenId);
            userRewardPerTokenPaid[tokenId] = rewardPerTokenStored;
        }

        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) / totalSupply;
    }

    function stake(address holder, uint256 tokenId, uint256 amount, uint256 expired, bytes calldata signature)
        external
        updateReward(holder, tokenId)
    {
        require(amount > 0, "amount = 0");
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked(holder, tokenId, amount, expired)));
        require(expired > block.timestamp, "withdrawal request expired" );
        require(!withrawalIds[hash], "used withdrawal request");
        require(SignatureChecker.isValidSignatureNow(owner, hash, signature), "invalid signature");
        balanceOf[tokenId] += amount;
        totalSupply += amount;
    }

    function earned(uint256 tokenId) public view returns (uint256) {
        return ((balanceOf[tokenId] * (rewardPerToken() - userRewardPerTokenPaid[tokenId])) / 1e18) + rewards[tokenId];
    }

    function getReward(uint256 tokenId) external updateReward(msg.sender, tokenId) {
        uint256 reward = rewards[tokenId];

        if (reward > 0) {
            delete rewards[tokenId];
            delete balanceOf[tokenId];
            bot.depositOllamaToken(tokenId, reward);
            emit Rewarded(msg.sender, tokenId, reward);
        }
    }

    function setRewardsDuration(uint256 _duration) external onlyOwner {
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
    }

    function notifyRewardAmount(uint256 _amount) external onlyOwner updateReward(address(0), 0) {
        if (block.timestamp >= finishAt) {
            rewardRate = _amount / duration;
        } else {
            uint256 remainingRewards = (finishAt - block.timestamp) * rewardRate;
            rewardRate = (_amount + remainingRewards) / duration;
        }

        require(rewardRate > 0, "reward rate = 0");
        require(rewardRate * duration <= ollamaToken.balanceOf(address(this)), "reward amount > balance");

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
