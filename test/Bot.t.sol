// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Bot} from "../src/Bot.sol";

contract BotTest is Test {
    Bot public bot;

    address public owner = address(0x1);

    address public mintAuthority = address(0x2);

    address public rewardAuthority = address(0x3);

    address public fundAuthority = address(0x4);

    constructor() {}
}
