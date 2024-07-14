// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Bot.sol";

contract CancelOrder is Script {
    function run(
        address bot, 
        address creditAccount, 
        address tokenIn,
        address tokenOut
    ) external {
        vm.startBroadcast();

        console.log("Submitting order...");

        Bot(bot).cancelOrder(creditAccount, tokenIn, tokenOut);

        vm.stopBroadcast();

        console.log("Order submitted!");
    }
}
