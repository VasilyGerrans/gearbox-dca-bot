// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {EXTERNAL_CALLS_PERMISSION} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {
    Bot, 
    ICreditFacadeV3, 
    MultiCall, 
    IERC20
} from "../src/Bot.sol";

contract TestBot is Test {
    address constant USDC_WHALE = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
    address constant RANDOM_ADDRESS = address(uint160(uint256(bytes32(keccak256("RANDOM_ADDRESS")))));
    uint256 constant TEST_AMOUNT = 1000000000;
    uint256 constant INITIAL_BALANCE = 10 * TEST_AMOUNT;
    uint256 constant FIVE_MINUTES = 5 * 60;
    uint256 constant FIVE_PERCENT_SLIPPAGE = 500;
    address constant TOkEN_OUT = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant TOKEN_IN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 memorisedTime;
    address testCreditAccount;
    address[] additionalConnector = [
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599 // wbtc
    ];

    Bot bot;

    function setUp() public {
        vm.createSelectFork("mainnet");

        vm.startPrank(USDC_WHALE);

        IERC20(TOKEN_IN).transfer(address(this), INITIAL_BALANCE);
        uint256 balance = IERC20(TOKEN_IN).balanceOf(address(this));
        assertEq(balance, INITIAL_BALANCE); 

        vm.stopPrank();

        bot = new Bot();

        MultiCall[] memory emptyCalls;
        testCreditAccount = bot.CREDIT_FACADE().openCreditAccount(address(this), emptyCalls, 0);
    }

    function test_revertNonexistentOrders() public {
        vm.expectRevert(Bot.OrderDoesNotExist.selector);
        bot.executeOrder(testCreditAccount);
    }

    function test_revertOrdersWithoutAllowance() public {
        bot.submitOrderToBot(
            testCreditAccount,
            TOKEN_IN,
            TOkEN_OUT,
            TEST_AMOUNT,
            FIVE_MINUTES,
            FIVE_PERCENT_SLIPPAGE,
            additionalConnector,
            false
        );

        vm.expectRevert(Bot.InsufficientAllowance.selector);
        bot.executeOrder(testCreditAccount);
    }

    function test_revertOrdersWithoutPermissions() public {
        bot.submitOrderToBot(
            testCreditAccount,
            TOKEN_IN,
            TOkEN_OUT,
            TEST_AMOUNT,
            FIVE_MINUTES,
            FIVE_PERCENT_SLIPPAGE,
            additionalConnector,
            false
        );

        IERC20(TOKEN_IN).approve(address(bot), 3 * TEST_AMOUNT);
        assertEq(IERC20(TOKEN_IN).allowance(address(this), address(bot)), 3 * TEST_AMOUNT);

        vm.expectRevert();
        bot.executeOrder(testCreditAccount);
    }

    function test_submitOrderToBot() public {
        IERC20(TOKEN_IN).approve(address(bot), 3 * TEST_AMOUNT);
        assertEq(IERC20(TOKEN_IN).allowance(address(this), address(bot)), 3 * TEST_AMOUNT);

        bot.CREDIT_FACADE().setBotPermissions(
            testCreditAccount,
            address(bot),
            EXTERNAL_CALLS_PERMISSION
        );

        uint256 ownerTokenInBefore = IERC20(TOKEN_IN).balanceOf(address(this));
        uint256 ownerTokenOutBefore = IERC20(TOkEN_OUT).balanceOf(address(this));
        uint256 caTokenInBefore = IERC20(TOKEN_IN).balanceOf(address(testCreditAccount));
        uint256 caTokenOutBefore = IERC20(TOkEN_OUT).balanceOf(address(testCreditAccount));

        bot.submitOrderToBot(
            testCreditAccount,
            TOKEN_IN,
            TOkEN_OUT,
            TEST_AMOUNT,
            FIVE_MINUTES,
            FIVE_PERCENT_SLIPPAGE,
            additionalConnector,
            true
        );

        memorisedTime = block.timestamp;

        uint256 ownerTokenInAfter = IERC20(TOKEN_IN).balanceOf(address(this));
        uint256 ownerTokenOutAfter = IERC20(TOkEN_OUT).balanceOf(address(this));
        uint256 caTokenInAfter = IERC20(TOKEN_IN).balanceOf(address(testCreditAccount));
        uint256 caTokenOutAfter = IERC20(TOkEN_OUT).balanceOf(address(testCreditAccount));

        assertEq(ownerTokenInBefore, INITIAL_BALANCE);
        assertEq(ownerTokenInAfter, INITIAL_BALANCE - TEST_AMOUNT);
        assertEq(caTokenOutBefore, 0);
        assertNotEq(caTokenOutAfter, 0);
        assertEq(ownerTokenOutBefore, 0);
        assertEq(ownerTokenOutAfter, 0);
        assertEq(caTokenInBefore, 0);
        assertEq(caTokenInAfter, 0);

        vm.expectRevert(Bot.ExecutingTooEarly.selector);
        bot.executeOrder(testCreditAccount);

        vm.warp(memorisedTime + FIVE_MINUTES);

        bot.executeOrder(testCreditAccount);

        uint256 ownerTokenInAfterAfter = IERC20(TOKEN_IN).balanceOf(address(this));
        uint256 ownerTokenOutAfterAfter = IERC20(TOkEN_OUT).balanceOf(address(this));
        uint256 caTokenInAfterAfter = IERC20(TOKEN_IN).balanceOf(address(testCreditAccount));
        uint256 caTokenOutAfterAfter = IERC20(TOkEN_OUT).balanceOf(address(testCreditAccount));

        assertEq(ownerTokenInAfterAfter, INITIAL_BALANCE - 2 * TEST_AMOUNT);
        assertEq(ownerTokenOutAfterAfter, 0);
        assertEq(caTokenInAfterAfter, 0);
        assertGt(caTokenOutAfterAfter, caTokenOutAfter);

        vm.startPrank(RANDOM_ADDRESS);
        vm.deal(RANDOM_ADDRESS, 1 ether);

        vm.expectRevert(Bot.OnlyOrderPayer.selector);
        bot.cancelOrder(testCreditAccount);

        vm.stopPrank();

        Bot.UserOrder memory openUserOrder = bot.userOrders(testCreditAccount);

        bot.cancelOrder(testCreditAccount);

        Bot.UserOrder memory closedUserOrder = bot.userOrders(testCreditAccount);

        assertEq(openUserOrder.payer, address(this));
        assertEq(openUserOrder.tokenIn, TOKEN_IN);
        assertEq(openUserOrder.tokenOut, TOkEN_OUT);
        assertEq(openUserOrder.amount, TEST_AMOUNT);
        assertEq(openUserOrder.interval, FIVE_MINUTES);
        assertEq(openUserOrder.slippage, 500);

        assertEq(closedUserOrder.payer, address(0));
        assertEq(closedUserOrder.tokenIn, address(0));
        assertEq(closedUserOrder.tokenOut, address(0));
        assertEq(closedUserOrder.amount, 0);
        assertEq(closedUserOrder.interval, 0);
        assertEq(closedUserOrder.slippage, 0);

        vm.expectRevert(Bot.OrderDoesNotExist.selector);
        bot.executeOrder(testCreditAccount);
    }
}
