# Gearbox DCA Bot
This repo features a Bot.sol smart contract which implements the DCA strategy on Gearbox. It includes an ExecuteOrder.s.sol script which, if invoked at regular intervals with a wallet with sufficient gas, will fulfil the orders specified by the user.
## Running sripts
After git cloning the repo, install npm dependencies 
```
npm i 
```
After that, all regular forge commands will work. 
To deploy Bot, run
```
forge script script/DeployBot.s.sol --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY> --broadcast
```
To execute an order, run
```
forge script script/ExecuteOrder.s.sol --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY> --sig "run(address,address,address,address)" <YOUR_BOT_ADDRESS> <YOUR_CREDIT_ACCOUNT_ADDRESS> <YOUR_TOKEN_IN> <YOUR_TOKEN_OUT> --broadcast
```
Other scripts can be invoked in similar fashion.
## How to use
As described in test/Bot.s.sol, the flow is:
1. Open CreditAccountV3 via Gearbox CreditFacadeV3 (note that this bot only supports V3).
2. Deploy bot.
3. Call CreditFacadeV3.setBotPermissions for the deployed bot with EXTERNAL_CALLS_PERMISSION enabled.
4. Approve the bot the desired amount of tokenIn (for a long-term DCA strategy, it would make sense to make a max approve).
5. Submit order directly to the Bot from the wallet which will pay into the DCA, or with permit as illustrated in test/Bot.s.sol.
6. Setup call to script/ExecuteOrder.s.sol at regular intervals (CRON or something fancier), or setup Keepers/Gelato/etc. with equivalent logic.
7. Once the user wants to actually withdraw the accumulated funds from the credit account, he should do so as described in the Gearbox docs: https://dev.gearbox.fi/credit/multicall/withdraw-collateral

## Notes
* Once an order is submitted, anyone can execute it at the allotted intervals. The only way to prevent it from working is to cancel order or to set approve for the token to the bot back to 0.
* This bot is designed to be used by multiple users, with unlimited credit accounts and unlimited possible in/out token pairs on each credit account.
* The bot is NOT designed to receive any ether or tokens.
* This repo hardcodes Ethereum Mainnet addresses everywhere.
* Existing orders can be edited by submitting a new order for the same credit account, token in and token out.
