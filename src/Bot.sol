// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IBot.sol";
import {Bit} from "./Bit.sol";

contract Bot is ERC721, Ownable, Pausable, IBot {
    IERC20 public immutable ollamaToken;

    uint8 public constant MaxModelId = 59;

    struct Withdraw {
        uint32 releaseTime0;
        uint32 releaseTime1;
        uint192 amount;
    }

    uint64 public ModelPrice = 1024;

    uint256 public VerificationNodePrice = 0.1 ether;

    mapping(uint256 => Profile) profiles;

    mapping(uint256 => uint256) balances;

    mapping(uint256 => Withdraw) withdraws;

    uint256 public totalSupply;

    uint128 public fundEther;

    uint128 public fundOllamaToken;

    address public mintAuthority;

    address public rewardAuthority;

    address public fundAuthority;

    string internal uri;

    event SyncedPoint(uint256 indexed tokenId, uint256 syncedPoints);

    event ModelPurchased(uint256 indexed tokenId, uint256 indexed modelId, uint64 points);

    event VerificationNodePurchased(uint256 indexed tokenId, uint256 indexed modelId, uint256 tokenAmount);

    event WithdrawCreated(uint256 indexed tokenId, uint256 amount, uint256 releaseTime0, uint256 releaseTime1);

    event WithdrawCanceled(uint256 indexed tokenId);

    event Withdrawed(uint256 indexed tokenId, address indexed recipient, uint256 amount);

    error invalid_signature();

    error zero_address();

    error already_synced();

    error not_holder();

    error insufficient_points();

    error insufficient_tokens();

    error invalid_model_id();

    error already_purchased();

    error not_purchased();

    error not_verification_node();

    error invalid_withdraw();

    error level_low_withdraw();

    error no_permission();

    error fund_withdraw_ether_error();

    modifier onlyHolder(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (owner != msg.sender) {
            revert not_holder();
        }
        _;
    }

    constructor(address _mintAuthority, address _rewardAuthority, address _fundAuthority, IERC20 _ollamaToken)
        ERC721("OLLAMABOT", "OLLAMABOT")
        Ownable(msg.sender)
    {
        mintAuthority = _mintAuthority;
        rewardAuthority = _rewardAuthority;
        fundAuthority = _fundAuthority;
        ollamaToken = _ollamaToken;
    }

    function setURI(string calldata _uri) external onlyOwner {
        uri = _uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return uri;
    }

    function setMintAuthority(address _authority) external onlyOwner {
        mintAuthority = _authority;
    }

    function setRewardAuthority(address _authority) external onlyOwner {
        rewardAuthority = _authority;
    }

    function setFundAuthority(address _authority) external onlyOwner {
        fundAuthority = _authority;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 tokenId, bytes calldata signature) external {
        bytes32 hash = keccak256(abi.encodePacked(to, tokenId));

        if (
            !SignatureChecker.isValidSignatureNow(
                mintAuthority, MessageHashUtils.toEthSignedMessageHash(hash), signature
            )
        ) {
            revert invalid_signature();
        }

        totalSupply += 1;
        _mint(to, tokenId);
    }

    function syncPoints(uint256 tokenId, uint64 points, bytes calldata signature) external {
        bytes32 hash = keccak256(abi.encodePacked(tokenId, points));
        if (
            !SignatureChecker.isValidSignatureNow(
                rewardAuthority, MessageHashUtils.toEthSignedMessageHash(hash), signature
            )
        ) {
            revert invalid_signature();
        }

        Profile storage profile = profiles[tokenId];

        if (points <= profile.syncedPoints) {
            revert already_synced();
        }
        profile.points += SafeCast.toUint64(points - profile.syncedPoints);
        profile.syncedPoints = SafeCast.toUint64(points);

        emit SyncedPoint(tokenId, points);
    }

    function getProfile(uint256 tokenId) external view returns (Profile memory) {
        return profiles[tokenId];
    }

    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function balanceOfPoint(uint256 tokenId) external view override returns (uint256) {
        return profiles[tokenId].points;
    }

    function purchaseModel(uint256 tokenId, uint8 modelId) external onlyHolder(tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];

        uint8 index = modelId * 2;

        uint8 purchased = Bit.bit(profile.models, index);

        if (purchased == 1) {
            revert already_purchased();
        }

        if (profile.points < ModelPrice) {
            revert insufficient_points();
        }

        profile.points -= ModelPrice;

        emit ModelPurchased(tokenId, modelId, ModelPrice);
    }

    function purchaseVerificationModel(uint256 tokenId, uint8 modelId) external payable onlyHolder(tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];

        uint8 index = modelId * 2;

        uint8 purchased = Bit.bit(profile.models, index);

        if (purchased == 0) {
            // no purchase
            revert not_purchased();
        }

        uint8 ifVerificationNode = Bit.bit(profile.models, index + 1);

        if (ifVerificationNode == 1) {
            revert already_purchased();
        }

        if (msg.value != VerificationNodePrice) {
            revert insufficient_tokens();
        }

        profile.models = SafeCast.toUint120(Bit.setBit(profile.models, index + 1));
        profile.level += 1;
        emit VerificationNodePurchased(tokenId, modelId, VerificationNodePrice);
    }

    function depositOllmaToken(uint256 tokenId, uint256 amount) external onlyHolder(tokenId) {
        SafeERC20.safeTransferFrom(ollamaToken, msg.sender, address(this), amount);
        balances[tokenId] += amount;
    }

    function createWithdrawRequest(uint256 tokenId, uint256 amount) external onlyHolder(tokenId) {
        Withdraw storage withdraw = withdraws[tokenId];
        balances[tokenId] -= amount;
        withdraw.releaseTime0 = SafeCast.toUint32(block.timestamp);
        (uint32 releaseTime0, uint32 releaseTime1) = _calculateLockTime(tokenId);
        withdraw.releaseTime0 = releaseTime0;
        withdraw.releaseTime1 = releaseTime1;
        withdraw.amount += SafeCast.toUint192(amount);

        emit WithdrawCreated(tokenId, amount, releaseTime0, releaseTime1);
    }

    function cancelWithdrawRequest(uint256 tokenId) external onlyHolder(tokenId) {
        Withdraw memory withdraw = withdraws[tokenId];

        if (withdraw.amount == 0) {
            revert invalid_withdraw();
        }

        delete withdraws[tokenId];
        emit WithdrawCanceled(tokenId);
    }

    function doWithdraw(uint256 tokenId, address recipient) external onlyHolder(tokenId) {
        Withdraw storage withdraw = withdraws[tokenId];

        uint256 value = _withdrawValue(withdraw);

        delete withdraws[tokenId];

        SafeERC20.safeTransfer(ollamaToken, recipient, value);
        emit Withdrawed(tokenId, recipient, value);
    }

    function withdrawFundEther(address payable recipient) external {
        if (msg.sender != fundAuthority) {
            revert no_permission();
        }

        (bool ok,) = recipient.call{value: fundEther}("");
        if (!ok) {
            revert fund_withdraw_ether_error();
        }
        fundEther = 0;
    }

    function withdrawFundOllamaToken(address recipient) external {
        if (msg.sender != fundAuthority) {
            revert no_permission();
        }

        SafeERC20.safeTransfer(ollamaToken, recipient, fundOllamaToken);
        fundOllamaToken = 0;
    }

    function _withdrawValue(Withdraw storage withdraw) internal view returns (uint256) {
        if (withdraw.amount == 0 || block.timestamp < withdraw.releaseTime0) {
            revert invalid_withdraw();
        }

        if (block.timestamp < withdraw.releaseTime1) {
            return (block.timestamp - withdraw.releaseTime0) * withdraw.amount
                / (withdraw.releaseTime1 - withdraw.releaseTime0);
        }

        return withdraw.amount;
    }

    function _calculateLockTime(uint256 tokenId) internal view returns (uint32, uint32) {
        Profile memory profile = profiles[tokenId];
        uint32 cur = SafeCast.toUint32(block.timestamp);

        uint256 level = profile.level;

        if (level < 3) {
            revert level_low_withdraw();
        }

        if (level < 6) {
            return (cur + 90 days, cur + 180 days);
        }

        if (level < 9) {
            return (cur + 60 days, cur + 120 days);
        }

        return (cur + 30 days, cur + 60 days);
    }
}
