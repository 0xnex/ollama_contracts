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
import "./IPricePolicy.sol";
import "./Bit.sol";

contract Bot is ERC721, Ownable, Pausable, IBot {
    uint8 public constant MaxModelId = 25; // every model takes 4 bit and used uint104 to save all model's status

    IERC20 public immutable ollamaToken;

    mapping(uint256 => Profile) profiles;

    mapping(uint256 => uint256) balances;

    mapping(bytes32 => uint256) verifcationBonds;

    uint256 public totalSupply;

    address public mintAuthority;

    address public rewardAuthority;

    address public fund;

    IPricePolicy public pricePolicy;

    string public baseURI = "";

    event SyncedPoint(uint256 indexed tokenId, uint256 syncedPoints);

    event ModelPurchased(uint256 indexed tokenId, uint256 indexed modelId, uint64 points);

    event BecomeVerificationNode(uint256 indexed tokenId, uint256 indexed modelId, uint256 tokenAmount);

    event QuitVerificationNode(uint256 indexed tokenId, uint256 indexed modelId, uint256 tokenAmount);

    event LevelUpgraded(uint256 indexed tokenId, uint8 level, uint64 points);

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

    modifier onlyHolder(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (owner != msg.sender) {
            revert not_holder();
        }
        _;
    }

    constructor(
        address _mintAuthority,
        address _rewardAuthority,
        address _fund,
        IPricePolicy _policy,
        IERC20 _ollamaToken
    ) ERC721("OLLAMABOT", "OLLAMABOT") Ownable(msg.sender) {
        mintAuthority = _mintAuthority;
        rewardAuthority = _rewardAuthority;
        fund = _fund;
        ollamaToken = _ollamaToken;
        pricePolicy = _policy;
    }

    function setURI(string calldata _uri) external onlyOwner {
        baseURI = _uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function updatePricePolicy(IPricePolicy _policy) external onlyOwner {
        pricePolicy = _policy;
    }

    function setMintAuthority(address _authority) external onlyOwner {
        if (_authority == address(0)) {
            revert zero_address();
        }
        mintAuthority = _authority;
    }

    function setRewardAuthority(address _authority) external onlyOwner {
        if (_authority == address(0)) {
            revert zero_address();
        }
        rewardAuthority = _authority;
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

    function syncPoints(uint256 tokenId, uint256 points, bytes calldata signature) external {
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

    function upgradeLevel(uint256 tokenId) external onlyHolder(tokenId) {
        uint64 needPoints = pricePolicy.getNetxLevelPoint(tokenId);
        Profile storage profile = profiles[tokenId];

        if (profile.points < needPoints) {
            revert insufficient_points();
        }

        profile.points -= needPoints;
        profile.level += 1;

        emit LevelUpgraded(tokenId, profile.level, needPoints);
    }

    function purchaseModel(uint256 tokenId, uint8 modelId) external onlyHolder(tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];

        uint8 index = modelId * 4;

        uint8 purchased = Bit.bit(profile.abilities, index);

        if (purchased > 0) {
            revert already_purchased();
        }

        uint64 needPoints = pricePolicy.getNextModelPoint(tokenId);

        if (profile.points < needPoints) {
            revert insufficient_points();
        }

        profile.points -= needPoints;

        emit ModelPurchased(tokenId, modelId, needPoints);
    }

    function becomeVerificationNode(uint256 tokenId, uint8 modelId) external onlyHolder(tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];

        uint8 index = modelId * 4;

        uint8 modelPurchased = Bit.bit(profile.abilities, index);

        if (modelPurchased == 0) {
            // no purchase
            revert not_purchased();
        }

        uint8 ifVerificationNode = Bit.bit(profile.abilities, index + 1);

        if (ifVerificationNode == 1) {
            revert already_purchased();
        }

        uint256 needTokens = pricePolicy.getNextVerifierTokenCount(tokenId);

        if (balances[tokenId] < needTokens) {
            revert insufficient_tokens();
        }

        bytes32 key = keccak256(abi.encodePacked(tokenId, modelId));
        verifcationBonds[key] = needTokens;
        balances[tokenId] -= needTokens;
        profile.abilities = SafeCast.toUint104(Bit.setBit(profile.abilities, index + 1));
        emit BecomeVerificationNode(tokenId, modelId, needTokens);
    }

    function quitVerificationNode(uint256 tokenId, uint8 modelId) external onlyHolder(tokenId) {
        if (modelId > MaxModelId) {
            revert invalid_model_id();
        }

        Profile storage profile = profiles[tokenId];
        uint8 index = modelId * 4 + 1;
        profile.abilities = SafeCast.toUint104(Bit.clearBit(profile.abilities, index));
        bytes32 key = keccak256(abi.encodePacked(tokenId, modelId));
        uint256 value = verifcationBonds[key];
        if (value == 0) {
            revert not_verification_node();
        }
        verifcationBonds[key] = 0;
        balances[tokenId] += value;
        emit QuitVerificationNode(tokenId, modelId, value);
    }

    function depositOllmaToken(uint256 tokenId, uint256 amount) external onlyHolder(tokenId) {
        SafeERC20.safeTransferFrom(ollamaToken, msg.sender, address(this), amount);
        balances[tokenId] += amount;
    }

    function withdrawOllmaToken(uint256 tokenId, uint256 amount) external onlyHolder(tokenId) {
        if (balances[tokenId] < amount) {
            revert insufficient_tokens();
        }

        uint64 ratio = pricePolicy.getWithdrawRatio(tokenId);

        uint256 toFund = amount * ratio / 10000;

        SafeERC20.safeTransfer(ollamaToken, msg.sender, amount - toFund);
        SafeERC20.safeTransfer(ollamaToken, fund, toFund);
        balances[tokenId] -= amount;
    }
}
