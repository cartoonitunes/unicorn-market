// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title UnicornMarket — fully onchain order book for Unicorn ↔ Unicorn Meat
/// @notice Hardcoded canonical token set, no admin keys, no offchain matching.
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

    // ─── Canonical Tokens (hardcoded for trust) ───────────────────────
    address public constant UNICORN = 0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7;
    address public constant W_UNICORN = 0x38a9aF1BD00f9988977095B31eb18d6D3D5dCA00;
    address public constant MEAT = 0xED6aC8de7c7CA7e3A22952e09C2a2A1232DDef9A;
    address public constant W_MEAT = 0xDFA208BB0B811cFBB5Fa3Ea98Ec37Aa86180e668;

    enum OrderStatus {
        Open,
        Filled,
        Cancelled
    }

    struct Order {
        address maker;
        address sellToken;
        address buyToken;
        uint256 sellAmountTotal;
        uint256 buyAmountTotal;
        uint256 sellAmountRemaining;
        uint256 buyAmountRemaining;
        uint64 createdAt;
        OrderStatus status;
    }

    Order[] public orders;

    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        address sellToken,
        address buyToken,
        uint256 sellAmountTotal,
        uint256 buyAmountTotal
    );

    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 sellAmountFilled,
        uint256 buyAmountPaid,
        uint256 sellAmountRemaining,
        uint256 buyAmountRemaining
    );

    event OrderCancelled(
        uint256 indexed orderId,
        address indexed maker,
        uint256 sellAmountRefunded
    );

    error InvalidToken();
    error InvalidAmount();
    error InvalidPair();
    error OrderNotOpen();
    error NotMaker();
    error Overfill();
    error TransferFailed();

    modifier validToken(address token) {
        if (token != UNICORN && token != W_UNICORN && token != MEAT && token != W_MEAT) {
            revert InvalidToken();
        }
        _;
    }

    function isUnicornSide(address token) public pure returns (bool) {
        return token == UNICORN || token == W_UNICORN;
    }

    function isMeatSide(address token) public pure returns (bool) {
        return token == MEAT || token == W_MEAT;
    }

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

        bool sellIsUnicorn = isUnicornSide(sellToken);
        bool buyIsUnicorn = isUnicornSide(buyToken);
        if (sellIsUnicorn == buyIsUnicorn) revert InvalidPair();

        _safeTransferFrom(sellToken, msg.sender, address(this), sellAmount);

        orderId = orders.length;
        orders.push(
            Order({
                maker: msg.sender,
                sellToken: sellToken,
                buyToken: buyToken,
                sellAmountTotal: sellAmount,
                buyAmountTotal: buyAmount,
                sellAmountRemaining: sellAmount,
                buyAmountRemaining: buyAmount,
                createdAt: uint64(block.timestamp),
                status: OrderStatus.Open
            })
        );

        emit OrderPlaced(orderId, msg.sender, sellToken, buyToken, sellAmount, buyAmount);
    }

    /// @notice Fill an order partially or fully.
    /// @param orderId Order id
    /// @param sellAmountToTake Amount of maker's sell token taker wants to receive
    function fillOrder(uint256 orderId, uint256 sellAmountToTake) external nonReentrant {
        _fillOrder(orderId, sellAmountToTake, msg.sender);
    }

    function fillOrderFull(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        _fillOrder(orderId, o.sellAmountRemaining, msg.sender);
    }

    function _fillOrder(uint256 orderId, uint256 sellAmountToTake, address taker) internal {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Open) revert OrderNotOpen();
        if (sellAmountToTake == 0) revert InvalidAmount();
        if (sellAmountToTake > o.sellAmountRemaining) revert Overfill();

        uint256 buyAmountToPay;
        if (sellAmountToTake == o.sellAmountRemaining) {
            // exact final fill closes all remaining dust deterministically
            buyAmountToPay = o.buyAmountRemaining;
        } else {
            // round up so maker is never underpaid on partials
            buyAmountToPay = _mulDivUp(sellAmountToTake, o.buyAmountTotal, o.sellAmountTotal);
            if (buyAmountToPay > o.buyAmountRemaining) revert Overfill();
        }

        o.sellAmountRemaining -= sellAmountToTake;
        o.buyAmountRemaining -= buyAmountToPay;

        if (o.sellAmountRemaining == 0) {
            o.status = OrderStatus.Filled;
        }

        _safeTransferFrom(o.buyToken, taker, o.maker, buyAmountToPay);
        _safeTransfer(o.sellToken, taker, sellAmountToTake);

        emit OrderFilled(
            orderId,
            taker,
            sellAmountToTake,
            buyAmountToPay,
            o.sellAmountRemaining,
            o.buyAmountRemaining
        );
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Open) revert OrderNotOpen();
        if (o.maker != msg.sender) revert NotMaker();

        uint256 refund = o.sellAmountRemaining;
        o.sellAmountRemaining = 0;
        o.buyAmountRemaining = 0;
        o.status = OrderStatus.Cancelled;

        _safeTransfer(o.sellToken, msg.sender, refund);

        emit OrderCancelled(orderId, msg.sender, refund);
    }

    function orderCount() external view returns (uint256) {
        return orders.length;
    }

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getOpenOrderIds() external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i; i < orders.length; i++) {
            if (orders[i].status == OrderStatus.Open) count++;
        }

        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < orders.length; i++) {
            if (orders[i].status == OrderStatus.Open) ids[idx++] = i;
        }
        return ids;
    }

    function getOrdersByMaker(address maker) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i; i < orders.length; i++) {
            if (orders[i].maker == maker) count++;
        }

        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < orders.length; i++) {
            if (orders[i].maker == maker) ids[idx++] = i;
        }
        return ids;
    }

    /// @notice Generic orderbook query for any allowed pair.
    function getOrderBook(address sellToken, address buyToken) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i; i < orders.length; i++) {
            Order storage o = orders[i];
            if (o.status == OrderStatus.Open && o.sellToken == sellToken && o.buyToken == buyToken) {
                count++;
            }
        }

        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < orders.length; i++) {
            Order storage o = orders[i];
            if (o.status == OrderStatus.Open && o.sellToken == sellToken && o.buyToken == buyToken) {
                ids[idx++] = i;
            }
        }
        return ids;
    }

    /// @notice Primary market asks: makers selling UNICORN for W_MEAT.
    function getPrimaryAsks() external view returns (uint256[] memory) {
        return this.getOrderBook(UNICORN, W_MEAT);
    }

    /// @notice Primary market bids: makers selling W_MEAT for UNICORN.
    function getPrimaryBids() external view returns (uint256[] memory) {
        return this.getOrderBook(W_MEAT, UNICORN);
    }

    function _mulDivUp(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        // ceil(a*b/d) = (a*b + d - 1) / d
        return (a * b + d - 1) / d;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        uint256 toBefore = IERC20(token).balanceOf(to);
        uint256 fromBefore = IERC20(token).balanceOf(address(this));

        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        if (!ok) revert TransferFailed();

        // Standard ERC20 path: empty return data OR true.
        if (data.length == 0 || abi.decode(data, (bool))) return;

        // Legacy-token fallback: some old contracts mutate state but return false.
        uint256 toAfter = IERC20(token).balanceOf(to);
        uint256 fromAfter = IERC20(token).balanceOf(address(this));
        if (toAfter < toBefore + amount || fromAfter + amount > fromBefore) {
            revert TransferFailed();
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        uint256 toBefore = IERC20(token).balanceOf(to);
        uint256 fromBefore = IERC20(token).balanceOf(from);

        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!ok) revert TransferFailed();

        // Standard ERC20 path: empty return data OR true.
        if (data.length == 0 || abi.decode(data, (bool))) return;

        // Legacy-token fallback: some old contracts mutate state but return false.
        uint256 toAfter = IERC20(token).balanceOf(to);
        uint256 fromAfter = IERC20(token).balanceOf(from);
        if (toAfter < toBefore + amount || fromAfter + amount > fromBefore) {
            revert TransferFailed();
        }
    }
}
