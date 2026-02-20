// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title UnicornMarket — Peer-to-peer order book for Unicorn ↔ Unicorn Meat trading
/// @notice Supports both original and wrapped versions of Unicorns and Unicorn Meat.
///         No AMM, no fees, no admin keys. Pure peer-to-peer exchange.
/// @dev    Tokens are escrowed in the contract on order placement and released atomically on fill.
contract UnicornMarket {
    // ─── Reentrancy Guard ──────────────────────────────────────────────
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    // ─── Token Registry ────────────────────────────────────────────────
    // Original Unicorns (2016, 0 decimals, 2717 supply)
    address public constant UNICORN = 0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7;
    // Wrapped Unicorn (0 decimals)
    address public constant W_UNICORN = 0x38a9aF1BD00f9988977095B31eb18d6D3D5dCA00;
    // Original Unicorn Meat (2016, 3 decimals, 100M supply)
    address public constant MEAT = 0xED6aC8de7c7CA7e3A22952e09C2a2A1232DDef9A;
    // Wrapped Unicorn Meat (3 decimals)
    address public constant W_MEAT = 0xDFA208BB0B811cFBB5Fa3Ea98Ec37Aa86180e668;

    // ─── Order Structure ───────────────────────────────────────────────
    struct Order {
        address maker;
        address sellToken;      // Token being sold (escrowed)
        address buyToken;       // Token wanted in return
        uint256 sellAmount;     // Amount escrowed
        uint256 buyAmount;      // Amount requested from taker
        uint64  createdAt;
        bool    filled;
        bool    cancelled;
    }

    Order[] public orders;

    // ─── Events ────────────────────────────────────────────────────────
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );

    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );

    event OrderCancelled(uint256 indexed orderId, address indexed maker);

    // ─── Errors ────────────────────────────────────────────────────────
    error InvalidToken();
    error InvalidAmount();
    error InvalidPair();
    error OrderNotOpen();
    error NotMaker();
    error TransferFailed();

    // ─── Modifiers ─────────────────────────────────────────────────────
    modifier validToken(address token) {
        if (token != UNICORN && token != W_UNICORN && token != MEAT && token != W_MEAT) {
            revert InvalidToken();
        }
        _;
    }

    /// @notice Returns true if the token is a Unicorn variant (original or wrapped)
    function isUnicornSide(address token) public pure returns (bool) {
        return token == UNICORN || token == W_UNICORN;
    }

    /// @notice Returns true if the token is a Meat variant (original or wrapped)
    function isMeatSide(address token) public pure returns (bool) {
        return token == MEAT || token == W_MEAT;
    }

    // ─── Place Order ───────────────────────────────────────────────────
    /// @notice Place a new order. Sell token is escrowed in the contract.
    /// @param sellToken The token you are selling (must be a valid Unicorn/Meat token)
    /// @param buyToken  The token you want (must be on the opposite side)
    /// @param sellAmount Amount of sellToken to escrow
    /// @param buyAmount  Amount of buyToken you want in return
    /// @return orderId The ID of the newly created order
    function placeOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    )
        external
        nonReentrant
        validToken(sellToken)
        validToken(buyToken)
        returns (uint256 orderId)
    {
        if (sellAmount == 0 || buyAmount == 0) revert InvalidAmount();

        // Must be trading Unicorn side ↔ Meat side (no same-side trades)
        bool sellIsUnicorn = isUnicornSide(sellToken);
        bool buyIsUnicorn = isUnicornSide(buyToken);
        if (sellIsUnicorn == buyIsUnicorn) revert InvalidPair();

        // Escrow sell tokens
        bool success = IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
        if (!success) revert TransferFailed();

        orderId = orders.length;
        orders.push(Order({
            maker: msg.sender,
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            createdAt: uint64(block.timestamp),
            filled: false,
            cancelled: false
        }));

        emit OrderPlaced(orderId, msg.sender, sellToken, buyToken, sellAmount, buyAmount);
    }

    // ─── Fill Order ────────────────────────────────────────────────────
    /// @notice Fill an open order. Taker sends buyAmount to maker, receives escrowed sellAmount.
    /// @param orderId The order to fill
    function fillOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        if (o.filled || o.cancelled) revert OrderNotOpen();

        o.filled = true;

        // Taker sends buyToken to maker
        bool takerPay = IERC20(o.buyToken).transferFrom(msg.sender, o.maker, o.buyAmount);
        if (!takerPay) revert TransferFailed();

        // Contract releases escrowed sellToken to taker
        bool release = IERC20(o.sellToken).transfer(msg.sender, o.sellAmount);
        if (!release) revert TransferFailed();

        emit OrderFilled(orderId, msg.sender, o.sellToken, o.buyToken, o.sellAmount, o.buyAmount);
    }

    // ─── Cancel Order ──────────────────────────────────────────────────
    /// @notice Cancel your own open order and reclaim escrowed tokens.
    /// @param orderId The order to cancel
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        if (o.filled || o.cancelled) revert OrderNotOpen();
        if (o.maker != msg.sender) revert NotMaker();

        o.cancelled = true;

        // Return escrowed tokens to maker
        bool refund = IERC20(o.sellToken).transfer(msg.sender, o.sellAmount);
        if (!refund) revert TransferFailed();

        emit OrderCancelled(orderId, msg.sender);
    }

    // ─── View Functions ────────────────────────────────────────────────

    /// @notice Total number of orders ever created
    function orderCount() external view returns (uint256) {
        return orders.length;
    }

    /// @notice Get a single order by ID
    function getOrder(uint256 orderId)
        external
        view
        returns (
            address maker,
            address sellToken,
            address buyToken,
            uint256 sellAmount,
            uint256 buyAmount,
            uint64  createdAt,
            bool    filled,
            bool    cancelled
        )
    {
        Order storage o = orders[orderId];
        return (o.maker, o.sellToken, o.buyToken, o.sellAmount, o.buyAmount, o.createdAt, o.filled, o.cancelled);
    }

    /// @notice Get all open (unfilled, uncancelled) order IDs
    /// @dev    For off-chain consumption. May be gas-heavy with many orders.
    function getOpenOrderIds() external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i; i < orders.length; i++) {
            if (!orders[i].filled && !orders[i].cancelled) count++;
        }
        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < orders.length; i++) {
            if (!orders[i].filled && !orders[i].cancelled) {
                ids[idx++] = i;
            }
        }
        return ids;
    }

    /// @notice Get all order IDs for a specific maker
    function getOrdersByMaker(address maker) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i; i < orders.length; i++) {
            if (orders[i].maker == maker) count++;
        }
        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < orders.length; i++) {
            if (orders[i].maker == maker) {
                ids[idx++] = i;
            }
        }
        return ids;
    }

    /// @notice Get open orders for a specific trading pair (e.g., all "selling Unicorns for Meat" orders)
    /// @param sellToken Filter by sell token
    /// @param buyToken  Filter by buy token
    function getOrderBook(address sellToken, address buyToken) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i; i < orders.length; i++) {
            Order storage o = orders[i];
            if (!o.filled && !o.cancelled && o.sellToken == sellToken && o.buyToken == buyToken) {
                count++;
            }
        }
        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < orders.length; i++) {
            Order storage o = orders[i];
            if (!o.filled && !o.cancelled && o.sellToken == sellToken && o.buyToken == buyToken) {
                ids[idx++] = i;
            }
        }
        return ids;
    }
}
