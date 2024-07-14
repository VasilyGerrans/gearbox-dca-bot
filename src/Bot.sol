// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {IRouterV3, RouterResult} from "@gearbox-protocol/liquidator-v2-contracts/contracts/interfaces/IRouterV3.sol";
import {MultiCall} from "@gearbox-protocol/core-v2/contracts/libraries/MultiCall.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Bot
 */
contract Bot {
    using SafeERC20 for IERC20;

    // Hardcoded Ethereum Mainnet addresses
    IRouterV3 private constant ROUTER =
        IRouterV3(0xA6FCd1fE716aD3801C71F2DE4E7A15f3a6994835);
    ICreditFacadeV3 public constant CREDIT_FACADE =
        ICreditFacadeV3(0x9Ab55e5c894238812295A31BdB415f00f7626792);

    struct UserOrder {
        address payer; // Address initiating the order
        address tokenIn; // Address of the token to transfer from payer to credit account
        address tokenOut; // Address of the token to receive after swap
        uint256 amount; // Amount of tokenIn to transfer or swap
        uint256 interval; // Time interval between successive executions (in seconds)
        uint256 lastUpdated; // Timestamp of the last execution
        uint256 slippage; // Acceptable slippage percentage for swap
        address[] additionalConnectors; // Additional connectors for swap (in addition to default)
    }

    error ExecutingTooEarly();
    error InsufficientAllowance();
    error OrderDoesNotExist();
    error OnlyOrderPayer();

    mapping(address => UserOrder) private _userOrders;

    // Hardcoded recommended connector addresses for RouterV3 as per GearBox documentation
    // https://dev.gearbox.fi/system-contracts/router#findonetokenpath
    address[] private _defaultConnectors = [
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
        0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
        0x853d955aCEf822Db058eb8505911ED77F175b99e // FRAX
    ];

    /**
     * @dev Returns the user order details for a given credit account.
     * @dev Implemented separately to return UserOrder struct instead of tuple.
     * @param creditAccount Address of the credit account to query.
     * @return UserOrder struct containing the order details.
     */
    function userOrders(
        address creditAccount
    ) external view returns (UserOrder memory) {
        return _userOrders[creditAccount];
    }

    /**
     * @dev Submits an order to the bot. If `begin` is true, executes the order immediately after submission.
     * @param creditAccount Address of the credit account to associate the order with.
     * @param tokenIn Address of the token to transfer from the payer to the credit account or swap from.
     * @param tokenOut Address of the token to receive after swap.
     * @param amount Amount of `tokenIn` to transfer or swap.
     * @param timeInterval Time interval between successive executions (in seconds).
     * @param slippage Acceptable slippage percentage for swap.
     * @param additionalConnectors Additional connectors to use for swap (in addition to default connectors).
     * @param begin Flag indicating whether to execute the order immediately after submission.
     */
    function submitOrderToBot(
        address creditAccount,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 timeInterval,
        uint256 slippage,
        address[] calldata additionalConnectors,
        bool begin
    ) external {
        _submitOrderToBot(
            msg.sender,
            creditAccount,
            tokenIn,
            tokenOut,
            amount,
            timeInterval,
            slippage,
            additionalConnectors
        );
        if (begin) _executeOrder(creditAccount);
    }

    /**
     * @dev Cancels an existing order associated with the caller's credit account.
     * @param creditAccount Address of the credit account associated with the order to cancel.
     */
    function cancelOrder(address creditAccount) external {
        _cancelOrder(creditAccount);
    }

    /**
     * @dev Executes the order associated with the caller's credit account. We expect the RouterV3 to include
     *      checks on slippage that will revert swaps that don't meet our criteria as per documentation
     *      https://dev.gearbox.fi/system-contracts/router#findonetokenpath. findOneTokenPath is invoked
     *      every time because the optimal path can change.
     * @param creditAccount Address of the credit account associated with the order to execute.
     */
    function executeOrder(address creditAccount) external {
        _executeOrder(creditAccount);
    }

    function _submitOrderToBot(
        address payer,
        address creditAccount,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 timeInterval,
        uint256 slippage,
        address[] calldata additionalConnectors
    ) internal {
        _userOrders[creditAccount] = UserOrder({
            payer: payer,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amount: amount,
            interval: timeInterval,
            lastUpdated: 0,
            slippage: slippage,
            additionalConnectors: additionalConnectors
        });
    }

    function _cancelOrder(address creditAccount) internal {
        UserOrder memory order = _userOrders[creditAccount];

        if (msg.sender != order.payer) revert OnlyOrderPayer();

        address[] memory emptyConnectors;

        order = UserOrder({
            payer: address(0),
            tokenIn: address(0),
            tokenOut: address(0),
            amount: 0,
            interval: 0,
            lastUpdated: 0,
            slippage: 0,
            additionalConnectors: emptyConnectors
        });

        _userOrders[creditAccount] = order;
    }

    function _executeOrder(address creditAccount) internal {
        UserOrder memory order = _userOrders[creditAccount];

        if (order.payer == address(0)) revert OrderDoesNotExist();
        if (order.lastUpdated + order.interval > block.timestamp)
            revert ExecutingTooEarly();
        if (
            IERC20(order.tokenIn).allowance(order.payer, address(this)) <
            order.amount
        ) revert InsufficientAllowance();

        IERC20(order.tokenIn).safeTransferFrom(
            order.payer,
            creditAccount,
            order.amount
        );

        RouterResult memory rResult = ROUTER.findOneTokenPath(
            order.tokenIn,
            order.amount,
            order.tokenOut,
            creditAccount,
            _concatArrays(_defaultConnectors, order.additionalConnectors),
            order.slippage
        );

        CREDIT_FACADE.botMulticall(creditAccount, rResult.calls);

        order.lastUpdated = block.timestamp;

        _userOrders[creditAccount] = order;
    }

    function _concatArrays(
        address[] memory array1,
        address[] memory array2
    ) internal pure returns (address[] memory array3) {
        array3 = new address[](array1.length + array2.length);

        for (uint256 i = 0; i < array1.length; i++) {
            array3[i] = array1[i];
        }

        for (uint256 i = 0; i < array2.length; i++) {
            array3[array1.length + i] = array2[i];
        }
    }
}
