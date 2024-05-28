// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";

import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Bot} from "../src/Bot.sol";
import {OllamaToken} from "../src/OllamaToken.sol";

contract TestBot is Bot {
    constructor(address _authority, address _fund, IERC20 _ollamaToken) Bot(_authority, _fund, _ollamaToken) {}

    function expose_calculateLockTime(Profile memory profile) external view returns (uint32, uint32) {
        return super._calculateLockTime(profile);
    }

    function expose_withdrawValue(Withdraw memory withdraw) external view returns (uint256) {
        return super._withdrawValue(withdraw);
    }

    function setProfile(uint256 tokenId, Profile memory profile) external {
        profiles[tokenId] = profile;
    }
}

contract BotTest is Test {
    using stdStorage for StdStorage;

    TestBot public bot;

    address owner = address(0x1);

    uint256 authorityPk = 0x1;

    address authority = vm.addr(authorityPk);

    uint256 fundPk = 0x2;

    address fund = vm.addr(fundPk);

    address holder0 = address(0x10);

    address holder1 = address(0x11);

    address holder2 = address(0x12);

    address holder3 = address(0x12);

    OllamaToken public ollamaToken = new OllamaToken();

    function setUp() public {
        bot = new TestBot(authority, fund, ollamaToken);
        ollamaToken.mint(holder1, 10000e18);
        bot.mint(holder1);

        vm.startPrank(holder1);
        ollamaToken.approve(address(bot), type(uint256).max);
        bot.depositOllmaToken(1, 10000e18);
        vm.stopPrank();
    }

    function testAdminMethods() public {
        string memory uri = "https://test.com/";
        bot.setURI(uri);
        assertEq(bot.uri(), uri);

        assertEq(bot.authority(), authority);
        assertEq(bot.fund(), fund);

        address newAuth = address(0x101);
        bot.setAuthority(newAuth);
        assertEq(bot.authority(), newAuth);

        address newFund = address(0x102);
        bot.setFund(newFund);
        assertEq(bot.fund(), newFund);

        bot.pause();
        assertEq(bot.paused(), true);

        bot.unpause();
        assertEq(bot.paused(), false);
    }

    function testMint() public {
        vm.prank(holder0);
        bot.mint(holder0);

        assertEq(bot.balanceOf(holder0), 1);
        assertEq(bot.ownerOf(2), holder0);
        assertEq(bot.totalSupply(), 2);

        (uint8 level, uint120 models, uint120 verifiers) = bot.profiles(1);
        assertEq(level, 1);
        assertEq(models, 1);
        assertEq(verifiers, 0);
    }

    function testUpgradeInsufficient() public {
        // mint nft
        bot.mint(holder0);

        vm.startPrank(holder0);

        vm.expectRevert();
        bot.upgrade(2, 0);
        vm.stopPrank();
    }

    function testUpgrade() public {
        // mint nft
        bot.mint(holder0);
        ollamaToken.mint(holder0, 100000e18);

        // ok
        vm.startPrank(holder0);

        ollamaToken.approve(address(bot), type(uint256).max);
        bot.depositOllmaToken(2, 1000e18);

        vm.expectEmit(true, true, true, true, address(bot));
        emit Bot.ModelUpgraded(holder0, 2, 0, bot.VerifierPrice());
        bot.upgrade(2, 0);

        (uint8 level, uint120 models, uint120 verifiers) = bot.profiles(2);
        assertEq(level, 2);
        assertEq(models, 1);
        assertEq(verifiers, 1);
        assertEq(bot.balances(2), (1000 - 768) * 10 ** 18);
        assertEq(ollamaToken.balanceOf(fund), 768 * 10 ** 18);
        vm.stopPrank();

        // upgrade identical model
        vm.startPrank(holder1);

        vm.expectRevert();
        bot.upgrade(2, 0);
        vm.stopPrank();

        // upgrade not purchased model
        vm.startPrank(holder1);
        vm.expectRevert();
        bot.upgrade(2, 1);
        vm.stopPrank();
    }

    function testPurchase() public {
        // mint nft
        bot.mint(holder0);
        ollamaToken.mint(holder0, 100000e18);

        // ok
        vm.startPrank(holder0);
        ollamaToken.approve(address(bot), type(uint256).max);
        bot.depositOllmaToken(2, 2000e18);
        bot.upgrade(2, 0);

        vm.expectEmit(true, true, true, true);
        emit Bot.ModelPurchased(holder0, 2, 5, bot.ModelPrice());
        bot.purchase(2, 5);

        (uint8 level, uint120 models, uint120 verifiers) = bot.profiles(2);
        assertEq(level, 3);
        assertEq(models, 2 ** 5 + 1);
        assertEq(verifiers, 1);
        assertEq(bot.balances(2), (2000 - 1024) * 10 ** 18);
        assertEq(ollamaToken.balanceOf(fund), 1024 * 10 ** 18);

        vm.stopPrank();

        // purchase identical model
        vm.startPrank(holder0);
        vm.expectRevert();
        bot.purchase(2, 5);
        vm.stopPrank();

        // purchase a new model before upgrade mode
        vm.startPrank(holder0);
        ollamaToken.approve(address(bot), type(uint256).max);
        bot.depositOllmaToken(2, 2000e18);
        vm.expectRevert();
        bot.purchase(2, 5);
        vm.stopPrank();
    }

    function testDepositOllamaToken() public {
        // token id not exists
        vm.startPrank(holder1);
        vm.expectRevert();
        bot.depositOllmaToken(3, 1000);
        vm.stopPrank();
    }

    function testWithdraw() public {
        // can not create withdraw request
        vm.startPrank(holder1);
        vm.expectRevert();
        bot.createWithdrawRequest(1, 10_000);
        vm.stopPrank();
    }

    function testCalculateLockTime() public {
        // ok
        uint256 cur = block.timestamp;

        // level 4
        Bot.Profile memory p1 = Bot.Profile({level: 4, models: 1, verifiers: 0});
        (uint32 r1b, uint32 r1e) = bot.expose_calculateLockTime(p1);
        assertEq(r1b, cur + 90 days);
        assertEq(r1e, cur + 180 days);

        // level 10
        Bot.Profile memory p2 = Bot.Profile({level: 10, models: 1, verifiers: 0});
        (uint32 r2b, uint32 r2e) = bot.expose_calculateLockTime(p2);
        assertEq(r2b, cur + 60 days);
        assertEq(r2e, cur + 120 days);

        // level 18
        Bot.Profile memory p3 = Bot.Profile({level: 18, models: 1, verifiers: 0});
        (uint32 r3b, uint32 r3e) = bot.expose_calculateLockTime(p3);
        assertEq(r3b, cur + 30 days);
        assertEq(r3e, cur + 60 days);

        // do not reach user lever for withdrawal
        Bot.Profile memory p0 = Bot.Profile({level: 1, models: 1, verifiers: 0});
        vm.expectRevert();
        bot.expose_calculateLockTime(p0);
    }

    function testWithdrawValue() public {
        Bot.Withdraw memory withdrawal = Bot.Withdraw({releaseTime0: 1000, releaseTime1: 2000, amount: 5000});

        // > releaseTime0 && < releaseTime1
        skip(1200); // block.timestamp starts from 1, cur = 1201
        console.log(block.timestamp);
        uint256 amount0 = bot.expose_withdrawValue(withdrawal);
        assertEq(amount0, 5000 * 201 / 1000);

        // after releaseTime1
        skip(800); // cur = 2001
        uint256 amount1 = bot.expose_withdrawValue(withdrawal);
        assertEq(amount1, 5000);

        // before releaseTime0
        rewind(1200); // cur = 801
        vm.expectRevert();
        bot.expose_withdrawValue(withdrawal);

        // amount is 0
        skip(1000); // cur = 1801
        withdrawal.amount = 0;
        vm.expectRevert();
        bot.expose_withdrawValue(withdrawal);
    }

    function testCreateWithdrawRequest() public {
        bot.setProfile(1, Bot.Profile({level: 8, models: 1, verifiers: 0}));

        vm.startPrank(holder1);
        vm.expectEmit(true, true, true, true);
        emit Bot.WithdrawCreated(holder1, 1, 5000, 1 + 90 days, 1 + 180 days);
        bot.createWithdrawRequest(1, 5000);
        (uint32 w0s, uint32 w0e, uint192 amount) = bot.withdrawals(1);
        assertEq(1 + 90 days, w0s);
        assertEq(1 + 180 days, w0e);
        assertEq(5000, amount);
        vm.stopPrank();
    }
}
