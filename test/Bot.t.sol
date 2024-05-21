// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Bot} from "../src/Bot.sol";
import {OllamaToken} from "../src/OllamaToken.sol";

contract BotTest is Test {
    Bot public bot;

    address owner = address(0x1);

    uint256 mintPk = 0x1;

    address mintAuthority = vm.addr(mintPk);

    uint256 rewardPk = 0x2;

    address rewardAuthority = vm.addr(rewardPk);

    address holder0 = address(0x10);

    address holder1 = address(0x11);

    address holder2 = address(0x12);

    address public fundAuthority = address(0x4);

    IERC20 public ollamaToken = new OllamaToken();

    function setUp() public {
        bot = new Bot(mintAuthority, rewardAuthority, fundAuthority, ollamaToken);
    }

    function testAdminMethods() public {
        string memory uri = "https://test.com/";
        bot.setURI(uri);
        assertEq(bot.uri(), uri);

        assertEq(bot.mintAuthority(), mintAuthority);
        assertEq(bot.rewardAuthority(), rewardAuthority);
        assertEq(bot.fundAuthority(), fundAuthority);

        address newMintAuth = address(0x11);
        bot.setMintAuthority(newMintAuth);
        assertEq(bot.mintAuthority(), newMintAuth);

        address newRewardAuthority = address(0x11);
        bot.setRewardAuthority(newRewardAuthority);
        assertEq(bot.rewardAuthority(), newRewardAuthority);

        address newFundAuthority = address(0x11);
        bot.setFundAuthority(newFundAuthority);
        assertEq(bot.fundAuthority(), newFundAuthority);

        bot.pause();
        assertEq(bot.paused(), true);

        bot.unpause();
        assertEq(bot.paused(), false);
    }

    function testMint() public {
        bytes32 hash = keccak256(abi.encodePacked(holder1, uint256(1)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintPk, MessageHashUtils.toEthSignedMessageHash(hash));
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
        bot.mint(holder1, uint256(1), signature);
        assertEq(bot.ownerOf(uint256(1)), holder1);
        assertEq(bot.totalSupply(), 1);

        bytes32 hash1 = keccak256(abi.encodePacked(holder1, uint256(2)));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(mintPk, MessageHashUtils.toEthSignedMessageHash(hash1));
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        bot.mint(holder1, uint256(2), signature1);
        assertEq(bot.ownerOf(uint256(2)), holder1);
        assertEq(bot.totalSupply(), 2);

        bytes32 hash2 = keccak256(abi.encodePacked(holder1, uint256(3)));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(mintPk, MessageHashUtils.toEthSignedMessageHash(hash2));
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        vm.expectRevert(Bot.invalid_signature.selector);
        bot.mint(holder1, uint256(4), signature2);
    }

    function testSyncPoints() public {
        // ok
        bytes32 hash = keccak256(abi.encodePacked(holder1, uint256(1)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintPk, MessageHashUtils.toEthSignedMessageHash(hash));
        bytes memory signature = abi.encodePacked(r, s, v);
        bot.mint(holder1, uint256(1), signature);

        bytes32 hash1 = keccak256(abi.encodePacked(uint256(1), uint64(1000)));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(rewardPk, MessageHashUtils.toEthSignedMessageHash(hash1));
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.expectEmit(true, true, true, true);
        emit Bot.PointSynced(uint256(1), uint64(1000));
        bot.syncPoints(uint256(1), uint64(1000), signature1);

        Bot.Profile memory profile = bot.getProfile(1);
        assertEq(profile.points, 1000);
        assertEq(profile.syncedPoints, 1000);

        // synced points less than previous
        bytes32 hash2 = keccak256(abi.encodePacked(uint256(1), uint64(800)));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(rewardPk, MessageHashUtils.toEthSignedMessageHash(hash2));
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        vm.expectRevert(Bot.already_synced.selector);
        bot.syncPoints(uint256(1), uint64(800), signature2);

        // invalid signature
        vm.expectRevert(Bot.invalid_signature.selector);
        bot.syncPoints(uint256(1), uint64(900), signature1);

        // token id not exists
        bytes32 hash3 = keccak256(abi.encodePacked(uint256(3), uint64(800)));
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(rewardPk, MessageHashUtils.toEthSignedMessageHash(hash3));
        bytes memory signature3 = abi.encodePacked(r3, s3, v3);
        vm.expectRevert();
        bot.syncPoints(uint256(3), uint64(800), signature3);
    }

    function testPurchaseModel() public {
        // mint nft
        bytes32 hash = keccak256(abi.encodePacked(holder1, uint256(1)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintPk, MessageHashUtils.toEthSignedMessageHash(hash));
        bytes memory signature = abi.encodePacked(r, s, v);
        bot.mint(holder1, uint256(1), signature);
        // sync points
        bytes32 hash1 = keccak256(abi.encodePacked(uint256(1), uint64(2000)));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(rewardPk, MessageHashUtils.toEthSignedMessageHash(hash1));
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        bot.syncPoints(uint256(1), uint64(2000), signature1);

        vm.deal(holder1, 1 ether);
        vm.prank(holder1);
        bot.purchaseVerificationModel{value: 0.1 ether}(1, 0);

        // ok
        vm.prank(holder1);
        vm.expectEmit(true, true, true, false);
        emit Bot.ModelPurchased(1, 1, 1024);
        bot.purchaseModel(1, 1);

        // purchase identical model
        vm.prank(holder1);
        vm.expectRevert();
        bot.purchaseModel(1, 1);
    }

    function testPurchaseVerificationNode() public {
        // mint nft
        bytes32 hash = keccak256(abi.encodePacked(holder1, uint256(1)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintPk, MessageHashUtils.toEthSignedMessageHash(hash));
        bytes memory signature = abi.encodePacked(r, s, v);
        bot.mint(holder1, uint256(1), signature);

        vm.deal(holder1, 1 ether);

        // price not match
        vm.prank(holder1);
        vm.expectRevert(Bot.insufficient_tokens.selector);
        emit Bot.VerificationNodePurchased(1, 0, 0.1 ether);
        bot.purchaseVerificationModel{value: 0.11 ether}(1, 0);

        vm.prank(holder1);
        vm.expectRevert(Bot.insufficient_tokens.selector);
        emit Bot.VerificationNodePurchased(1, 0, 0.1 ether);
        bot.purchaseVerificationModel{value: 0.8 ether}(1, 0);

        // ok
        vm.prank(holder1);
        vm.expectEmit(true, true, true, false);
        emit Bot.VerificationNodePurchased(1, 0, 0.1 ether);
        bot.purchaseVerificationModel{value: 0.1 ether}(1, 0);

        // upgrade identical model
        vm.prank(holder1);
        vm.expectRevert(Bot.already_purchased.selector);
        emit Bot.VerificationNodePurchased(1, 0, 0.1 ether);
        bot.purchaseVerificationModel{value: 0.1 ether}(1, 0);

        // upgrade no-purchased model
        vm.prank(holder1);
        vm.expectRevert(Bot.not_purchased.selector);
        emit Bot.VerificationNodePurchased(1, 1, 0.1 ether);
        bot.purchaseVerificationModel{value: 0.1 ether}(1, 1);
    }

    function testDepositOllamaToken() public {}
}
