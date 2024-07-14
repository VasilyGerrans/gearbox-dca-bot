// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Bot.sol";

contract DeployBot is Script {
    function run() external {
        vm.startBroadcast();

        Bot b = new Bot();

        vm.stopBroadcast();

        console.log("Bot deployed at:", address(b));
    }
}
