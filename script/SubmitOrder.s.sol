// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Bot.sol";

contract SubmitOrder is Script {
    function run(
        address bot, 
        address creditAccount, 
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 timeInterval,
        uint256 slippage,
        address[] calldata additionalConnectors,
        bool begin
    ) external {
        vm.startBroadcast();

        console.log("Submitting order...");

        Bot(bot).submitOrder(creditAccount, tokenIn, tokenOut, amount, timeInterval, slippage, additionalConnectors, begin);

        vm.stopBroadcast();

        console.log("Order submitted!");
    }
}
