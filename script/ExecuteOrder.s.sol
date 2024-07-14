// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Bot.sol";

/**
 * @title ExecuteOrder script
 * @dev Script to be run at regular intervals by off-chain bot server. Calls executeOrder without 
 *      broadcasting first, in order to not send transaction in cases where it will revert for some reason. 
 */
contract ExecuteOrder is Script {
    function run(address bot, address creditAccount, address tokenIn, address tokenOut) external {
        vm.createSelectFork("mainnet");

        console.log("Checking if order execution reverts...");

        Bot(bot).executeOrder(msg.sender, creditAccount, tokenIn, tokenOut);

        vm.startBroadcast();

        console.log("Executing order...");

        Bot(bot).executeOrder(msg.sender, creditAccount, tokenIn, tokenOut);

        vm.stopBroadcast();

        console.log("Order executed!");
    }
}
