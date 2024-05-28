// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {
    ERC721Enumerable,
    ERC721
} from "../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {SafeCast} from "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IBot.sol";
import {Bit} from "./Bit.sol";

contract Bot is ERC721Enumerable, Ownable, Pausable {
    // price of model
    uint256 public constant ModelPrice = 256e18;

    // price of verification node
    uint256 public constant VerifierPrice = 768e18;

    // max model Id
    uint8 public constant MaxModelId = 120;

    // ollam token
    IERC20 public immutable ollamaToken;

    // Withdraw struct to represent a withdrawal request
    struct Withdraw {
        uint32 releaseTime0; // The time after which the user can start withdrawing a portion of the amount
        uint32 releaseTime1; // The time after which the user can withdraw the entire amount
        uint192 amount; // The total amount available for withdrawal
    }

    // Mapping to store the withdrawal requests of each bot
    mapping(uint256 => Withdraw) public withdrawals;

    // Profile struct to represent a user's profile
    struct Profile {
        uint8 level; // The user's level
        uint120 models; // Bitmask representing purchased models (supports up to 120 models)
        uint120 verifiers; // Bitmask representing purchased verifiers (supports up to 120 models)
    }

    // Mapping to store profiles based on a tokenID
    mapping(uint256 => Profile) public profiles;

    // Balance of ollama token per tokenID
    mapping(uint256 => uint256) public balances;

    // address to receive funds
    address public fund;

    // address to maintain profile per token
    address public authority;

    // base uri
    string public uri;

    event ModelPurchased(address indexed owner, uint256 indexed tokenId, uint256 indexed modelId, uint256 amount);

    event ModelUpgraded(address indexed owner, uint256 indexed tokenId, uint256 indexed modelId, uint256 amount);

    event WithdrawCreated(
        address indexed owner, uint256 indexed tokenId, uint256 amount, uint256 releaseTime0, uint256 releaseTime1
    );

    event WithdrawCanceled(address indexed owner, uint256 indexed tokenId);

    event Withdrawed(address indexed owner, uint256 indexed tokenId, address indexed recipient, uint256 amount);

    error invalid_signature();

    error not_holder();

    error insufficient();

    error invalid_model_id();

    error already_purchased();

    error not_purchased();

    error invalid_withdraw();

    error withraw_not_allow();

    modifier onlyHolder(address owner, uint256 tokenId) {
        if (ownerOf(tokenId) != owner) {
            revert not_holder();
        }
        _;
    }

    constructor(address _authority, address _fund, IERC20 _ollamaToken)
        ERC721("OLLAMABOT", "OLLAMABOT")
        Ownable(msg.sender)
    {
        authority = _authority;
        fund = _fund;
        ollamaToken = _ollamaToken;
    }

    /**
     * =============================================================================
     * Admin
     * =============================================================================
     */
    function setURI(string calldata _uri) external onlyOwner {
        uri = _uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return uri;
    }

    function setAuthority(address _authority) external onlyOwner {
        authority = _authority;
    }

    function setFund(address _fund) external onlyOwner {
        fund = _fund;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * =============================================================================
     * Logic
     * =============================================================================
     */
    function mint(address to) external {
        uint256 id = totalSupply() + 1;
        _mint(to, id);
        profiles[id] = Profile({level: 1, models: 1, verifiers: 0});
    }

    function purchase(uint256 tokenId, uint8 modelId) external onlyHolder(msg.sender, tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];

        if (profile.level % 2 == 1) {
            revert not_purchased();
        }

        uint8 purchased = Bit.bit(profile.models, modelId);

        if (purchased == 1) {
            revert already_purchased();
        }

        balances[tokenId] -= ModelPrice;
        SafeERC20.safeTransfer(ollamaToken, fund, ModelPrice);
        profile.level = profile.level + 1;
        profile.models = SafeCast.toUint120(Bit.setBit(profile.models, modelId));
        emit ModelPurchased(msg.sender, tokenId, modelId, ModelPrice);
    }

    function upgrade(uint256 tokenId, uint8 modelId) external onlyHolder(msg.sender, tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];
        uint8 purchased = Bit.bit(profile.models, modelId);

        if (purchased == 0) {
            // no purchase
            revert not_purchased();
        }

        uint8 ifVerifier = Bit.bit(profile.verifiers, modelId);

        if (ifVerifier == 1) {
            revert already_purchased();
        }

        balances[tokenId] -= VerifierPrice;
        SafeERC20.safeTransfer(ollamaToken, fund, VerifierPrice);
        profile.verifiers = SafeCast.toUint120(Bit.setBit(profile.verifiers, modelId));
        profile.level += 1;
        emit ModelUpgraded(msg.sender, tokenId, modelId, VerifierPrice);
    }

    function depositOllmaToken(uint256 tokenId, uint256 amount) external onlyHolder(msg.sender, tokenId) {
        SafeERC20.safeTransferFrom(ollamaToken, msg.sender, address(this), amount);
        balances[tokenId] += amount;
    }

    function createWithdrawRequest(uint256 tokenId, uint256 amount) external onlyHolder(msg.sender, tokenId) {
        Withdraw storage withdraw = withdrawals[tokenId];
        balances[tokenId] -= amount;
        withdraw.releaseTime0 = SafeCast.toUint32(block.timestamp);
        (uint32 releaseTime0, uint32 releaseTime1) = _calculateLockTime(profiles[tokenId]);
        withdraw.releaseTime0 = releaseTime0;
        withdraw.releaseTime1 = releaseTime1;
        withdraw.amount += SafeCast.toUint192(amount);

        emit WithdrawCreated(msg.sender, tokenId, amount, releaseTime0, releaseTime1);
    }

    function cancelWithdrawRequest(uint256 tokenId) external onlyHolder(msg.sender, tokenId) {
        Withdraw memory withdraw = withdrawals[tokenId];

        if (withdraw.amount == 0) {
            revert invalid_withdraw();
        }

        balances[tokenId] = withdraw.amount;
        delete withdrawals[tokenId];
        emit WithdrawCanceled(msg.sender, tokenId);
    }

    function doWithdraw(uint256 tokenId, address recipient) external onlyHolder(msg.sender, tokenId) {
        Withdraw storage withdraw = withdrawals[tokenId];

        uint256 value = _withdrawValue(withdraw);

        delete withdrawals[tokenId];

        SafeERC20.safeTransfer(ollamaToken, recipient, value);
        emit Withdrawed(msg.sender, tokenId, recipient, value);
    }

    /**
     * =============================================================================
     * Internal
     * =============================================================================
     */
    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _withdrawValue(Withdraw memory withdraw) internal view returns (uint256) {
        if (withdraw.amount == 0 || block.timestamp <= withdraw.releaseTime0) {
            revert invalid_withdraw();
        }

        if (block.timestamp < withdraw.releaseTime1) {
            return (block.timestamp - withdraw.releaseTime0) * withdraw.amount
                / (withdraw.releaseTime1 - withdraw.releaseTime0);
        }

        return withdraw.amount;
    }

    function _calculateLockTime(Profile memory profile) internal view returns (uint32, uint32) {
        uint32 cur = SafeCast.toUint32(block.timestamp);

        uint256 level = profile.level;

        if (level < 4) {
            revert withraw_not_allow();
        }

        if (level < 10) {
            return (cur + 90 days, cur + 180 days);
        }

        if (level < 18) {
            return (cur + 60 days, cur + 120 days);
        }

        return (cur + 30 days, cur + 60 days);
    }
}
