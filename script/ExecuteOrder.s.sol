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
    function run(Bot bot, address creditAccount) external {
        vm.createSelectFork("mainnet");

        console.log("Checking if order execution reverts...");

        bot.executeOrder(creditAccount);

        vm.startBroadcast();

        console.log("Executing order...");

        bot.executeOrder(creditAccount);

        vm.stopBroadcast();

        console.log("Order executed!");
    }
}
