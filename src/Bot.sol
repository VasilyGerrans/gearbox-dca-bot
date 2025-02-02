// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {IRouterV3, RouterResult} from "@gearbox-protocol/liquidator-v2-contracts/contracts/interfaces/IRouterV3.sol";
import {MultiCall} from "@gearbox-protocol/core-v2/contracts/libraries/MultiCall.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SigUtils} from "./SigUtils.sol";
import {ArrayConcat} from "./lib/ArrayConcat.sol";

contract Bot is SigUtils {
    using SafeERC20 for IERC20;
    using ArrayConcat for address[];

    struct UserOrder {
        uint256 amount; // Amount of tokenIn to transfer or swap
        uint256 interval; // Time interval between successive executions (in seconds)
        uint256 lastUpdated; // Timestamp of the last execution
        uint256 slippage; // Acceptable slippage percentage for swap (in bps)
        address[] additionalConnectors; // Additional connectors for swap (in addition to default)
    }

    // Hardcoded Ethereum Mainnet addresses
    IRouterV3 private constant ROUTER =
        IRouterV3(0xA6FCd1fE716aD3801C71F2DE4E7A15f3a6994835);
    ICreditFacadeV3 public constant CREDIT_FACADE =
        ICreditFacadeV3(0x9Ab55e5c894238812295A31BdB415f00f7626792);

    // payer => CreditAccount => tokenIn => tokenOut => UserOrder
    mapping(address => mapping(address => mapping(address => mapping(address => UserOrder))))
        private _userOrders;

    // Hardcoded recommended connector addresses for RouterV3 as per GearBox documentation
    // https://dev.gearbox.fi/system-contracts/router#findonetokenpath
    address[] private _defaultConnectors = [
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
        0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
        0x853d955aCEf822Db058eb8505911ED77F175b99e // FRAX
    ];

    event OrderSubmitted(
        address indexed payer,
        address indexed creditAccount,
        address tokenIn,
        address tokenOut
    );

    event OrderCancelled(
        address indexed payer,
        address indexed creditAccount,
        address tokenIn,
        address tokenOut
    );

    event OrderExecuted(
        address indexed payer,
        address indexed creditAccount,
        address tokenIn,
        address tokenOut
    );

    error ExecutingTooEarly();
    error InsufficientAllowance();
    error OrderDoesNotExist();
    error PastDeadline();
    error InvalidSigner();

    /**
     * @notice Submits an order with a permit.
     * @param permit The permit containing order details.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     * @dev Decodes the permit data and submits an order if the permit is valid.
     * @dev Reverts with `PastDeadline` if the permit deadline has passed.
     * @dev Reverts with `InvalidSigner` if the recovered address is invalid or does not match the payer.
     */
    function submitOrderWithPermit(
        Permit calldata permit,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > permit.deadline) revert PastDeadline();

        address recoveredAddress = _recoverAddress(permit, v, r, s);

        if (recoveredAddress == address(0) || recoveredAddress != permit.payer)
            revert InvalidSigner();

        (
            uint256 amount,
            uint256 timeInterval,
            uint256 slippage,
            address[] memory additionalConnectors
        ) = abi.decode(permit.data, (uint256, uint256, uint256, address[]));

        _submitOrder(
            permit.payer,
            permit.creditAccount,
            permit.tokenIn,
            permit.tokenOut,
            amount,
            timeInterval,
            slippage,
            additionalConnectors
        );
    }

    /**
     * @notice Cancels an order with a permit.
     * @param permit The permit containing order details.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     * @dev Cancels an order if the permit is valid.
     * @dev Reverts with `PastDeadline` if the permit deadline has passed.
     * @dev Reverts with `InvalidSigner` if the recovered address is invalid or does not match the payer.
     */
    function cancelOrderWithPermit(
        Permit calldata permit,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > permit.deadline) revert PastDeadline();

        address recoveredAddress = _recoverAddress(permit, v, r, s);

        if (recoveredAddress == address(0) || recoveredAddress != permit.payer)
            revert InvalidSigner();

        _cancelOrder(
            permit.payer,
            permit.creditAccount,
            permit.tokenIn,
            permit.tokenOut
        );
    }

    /**
     * @dev Submits an order to the bot. If `begin` is true, executes the order immediately after submission.
     *      Can also be used to update information about an existing order.
     * @param creditAccount Address of the credit account to associate the order with.
     * @param tokenIn Address of the token to transfer from the payer to the credit account and swap from.
     * @param tokenOut Address of the token to receive after swap.
     * @param amount Amount of `tokenIn` to transfer or swap.
     * @param timeInterval Time interval between successive executions (in seconds).
     * @param slippage Acceptable slippage percentage for swap (in bps).
     * @param additionalConnectors Additional connectors to use for swap (in addition to default connectors).
     * @param begin Flag indicating whether to execute the order immediately after submission.
     */
    function submitOrder(
        address creditAccount,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 timeInterval,
        uint256 slippage,
        address[] calldata additionalConnectors,
        bool begin
    ) external {
        _submitOrder(
            msg.sender,
            creditAccount,
            tokenIn,
            tokenOut,
            amount,
            timeInterval,
            slippage,
            additionalConnectors
        );
        if (begin) _executeOrder(msg.sender, creditAccount, tokenIn, tokenOut);
    }

    /**
     * @dev Cancels an existing order associated with the caller's credit account.
     * @param creditAccount Address of the credit account associated with the order to cancel.
     * @param tokenIn Address of the token to transfer from the payer to the credit account and swap from.
     * @param tokenOut Address of the token to receive after swap.
     */
    function cancelOrder(
        address creditAccount,
        address tokenIn,
        address tokenOut
    ) external {
        _cancelOrder(msg.sender, creditAccount, tokenIn, tokenOut);
    }

    /**
     * @dev Executes the order associated with the caller's credit account. We expect the RouterV3 to include
     *      checks on slippage that will revert swaps that don't meet our criteria as per documentation
     *      https://dev.gearbox.fi/system-contracts/router#findonetokenpath. findOneTokenPath is invoked
     *      every time because the optimal path can change.
     * @param payer Address of the payer of the swaps.
     * @param creditAccount Address of the credit account associated with the order to execute.
     * @param tokenIn Address of the token to transfer from the payer to the credit account and swap from.
     * @param tokenOut Address of the token to receive after swap.
     */
    function executeOrder(
        address payer,
        address creditAccount,
        address tokenIn,
        address tokenOut
    ) external {
        _executeOrder(payer, creditAccount, tokenIn, tokenOut);
    }

    /**
     * @dev Returns the user order details for a given credit account.
     *      Implemented separately to return UserOrder struct instead of tuple.
     * @param payer Address of the payer of the swaps.
     * @param creditAccount Address of the credit account to query.
     * @param tokenIn Address of the token to transfer from the payer to the credit account and swap from.
     * @param tokenOut Address of the token to receive after swap.
     * @return UserOrder struct containing the order details.
     */
    function userOrders(
        address payer,
        address creditAccount,
        address tokenIn,
        address tokenOut
    ) external view returns (UserOrder memory) {
        return _userOrders[payer][creditAccount][tokenIn][tokenOut];
    }

    function _submitOrder(
        address payer,
        address creditAccount,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 timeInterval,
        uint256 slippage,
        address[] memory additionalConnectors
    ) internal {
        UserOrder memory order = _userOrders[payer][creditAccount][tokenIn][
            tokenOut
        ];

        _userOrders[payer][creditAccount][tokenIn][tokenOut] = UserOrder({
            amount: amount,
            interval: timeInterval,
            lastUpdated: order.lastUpdated,
            slippage: slippage,
            additionalConnectors: additionalConnectors
        });

        emit OrderSubmitted(payer, creditAccount, tokenIn, tokenOut);
    }

    function _cancelOrder(
        address payer,
        address creditAccount,
        address tokenIn,
        address tokenOut
    ) internal {
        UserOrder memory order = _userOrders[payer][creditAccount][tokenIn][
            tokenOut
        ];

        address[] memory emptyConnectors;
        order = UserOrder({
            amount: 0,
            interval: 0,
            lastUpdated: 0,
            slippage: 0,
            additionalConnectors: emptyConnectors
        });

        _userOrders[payer][creditAccount][tokenIn][tokenOut] = order;

        emit OrderCancelled(payer, creditAccount, tokenIn, tokenOut);
    }

    function _executeOrder(
        address payer,
        address creditAccount,
        address tokenIn,
        address tokenOut
    ) internal {
        UserOrder memory order = _userOrders[payer][creditAccount][tokenIn][
            tokenOut
        ];

        if (order.amount == 0) revert OrderDoesNotExist();
        if (order.lastUpdated + order.interval > block.timestamp)
            revert ExecutingTooEarly();
        if (IERC20(tokenIn).allowance(payer, address(this)) < order.amount)
            revert InsufficientAllowance();

        IERC20(tokenIn).safeTransferFrom(payer, creditAccount, order.amount);

        RouterResult memory rResult = ROUTER.findOneTokenPath(
            tokenIn,
            order.amount,
            tokenOut,
            creditAccount,
            _defaultConnectors.concat(order.additionalConnectors),
            order.slippage
        );

        CREDIT_FACADE.botMulticall(creditAccount, rResult.calls);

        order.lastUpdated = block.timestamp;

        _userOrders[payer][creditAccount][tokenIn][tokenOut] = order;

        emit OrderExecuted(payer, creditAccount, tokenIn, tokenOut);
    }
}
