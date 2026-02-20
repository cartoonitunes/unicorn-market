// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "../src/UnicornMarket.sol";

/// @notice Mainnet-fork tests for UnicornMarket (hardened).
contract UnicornMarketTest is Test {
    UnicornMarket market;

    address constant UNICORN   = 0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7;
    address constant W_UNICORN = 0x38a9aF1BD00f9988977095B31eb18d6D3D5dCA00;
    address constant MEAT      = 0xED6aC8de7c7CA7e3A22952e09C2a2A1232DDef9A;
    address constant W_MEAT    = 0xDFA208BB0B811cFBB5Fa3Ea98Ec37Aa86180e668;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc);

        assertGt(UNICORN.code.length, 0,   "UNICORN missing");
        assertGt(W_UNICORN.code.length, 0, "W_UNICORN missing");
        assertGt(MEAT.code.length, 0,      "MEAT missing");
        assertGt(W_MEAT.code.length, 0,    "W_MEAT missing");

        market = new UnicornMarket();
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _seedUnicorn(address to, uint256 amt) internal { deal(UNICORN, to, amt, false); }
    function _seedWUnicorn(address to, uint256 amt) internal { deal(W_UNICORN, to, amt, false); }
    function _seedWMeat(address to, uint256 amt) internal { deal(W_MEAT, to, amt, false); }

    // ════════════════════════════════════════════════════════════════
    // 1. PRIMARY PAIR: UNICORN ⇄ W_MEAT
    // ════════════════════════════════════════════════════════════════

    function test_placeAsk_unicornForWMeat() public {
        _seedUnicorn(alice, 10);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 3);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 3, 15_000_000);
        vm.stopPrank();

        assertEq(id, 0);
        assertEq(IERC20(UNICORN).balanceOf(alice), 7);
        assertEq(IERC20(UNICORN).balanceOf(address(market)), 3);

        UnicornMarket.Order memory o = market.getOrder(0);
        assertEq(o.maker, alice);
        assertEq(o.sellToken, UNICORN);
        assertEq(o.buyToken, W_MEAT);
        assertEq(o.sellAmountTotal, 3);
        assertEq(o.buyAmountTotal, 15_000_000);
        assertEq(o.sellAmountRemaining, 3);
        assertEq(o.buyAmountRemaining, 15_000_000);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Open));
    }

    function test_placeBid_wMeatForUnicorn() public {
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 25_000_000);
        uint256 id = market.placeOrder(W_MEAT, UNICORN, 25_000_000, 5);
        vm.stopPrank();

        assertEq(id, 0);
        assertEq(IERC20(W_MEAT).balanceOf(bob), 25_000_000);
        assertEq(IERC20(W_MEAT).balanceOf(address(market)), 25_000_000);
    }

    function test_fullFill() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(0, 2);
        vm.stopPrank();

        assertEq(IERC20(UNICORN).balanceOf(bob), 2);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 10_000_000);

        UnicornMarket.Order memory o = market.getOrder(0);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Filled));
        assertEq(o.sellAmountRemaining, 0);
        assertEq(o.buyAmountRemaining, 0);
    }

    function test_partialFill() public {
        _seedUnicorn(alice, 10);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 4);
        market.placeOrder(UNICORN, W_MEAT, 4, 20_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        UnicornMarket.Order memory o = market.getOrder(0);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Open));
        assertEq(o.sellAmountRemaining, 3);
        assertEq(o.buyAmountRemaining, 15_000_000);
        assertEq(IERC20(UNICORN).balanceOf(bob), 1);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 5_000_000);
    }

    function test_multiplePartialFills() public {
        _seedUnicorn(alice, 10);
        _seedWMeat(bob, 50_000_000);
        _seedWMeat(carol, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 4);
        market.placeOrder(UNICORN, W_MEAT, 4, 20_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        vm.startPrank(carol);
        IERC20(W_MEAT).approve(address(market), 15_000_000);
        market.fillOrder(0, 3);
        vm.stopPrank();

        UnicornMarket.Order memory o = market.getOrder(0);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Filled));
        assertEq(IERC20(UNICORN).balanceOf(bob), 1);
        assertEq(IERC20(UNICORN).balanceOf(carol), 3);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 20_000_000);
    }

    function test_fillOrderFull() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrderFull(0);
        vm.stopPrank();

        assertEq(IERC20(UNICORN).balanceOf(bob), 2);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 10_000_000);
        assertEq(uint256(market.getOrder(0).status), uint256(UnicornMarket.OrderStatus.Filled));
    }

    function test_cancelOrder() public {
        _seedUnicorn(alice, 5);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 3);
        market.placeOrder(UNICORN, W_MEAT, 3, 15_000_000);
        market.cancelOrder(0);
        vm.stopPrank();

        assertEq(IERC20(UNICORN).balanceOf(alice), 5);
        assertEq(uint256(market.getOrder(0).status), uint256(UnicornMarket.OrderStatus.Cancelled));
    }

    function test_cancelAfterPartial() public {
        _seedUnicorn(alice, 10);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 4);
        market.placeOrder(UNICORN, W_MEAT, 4, 20_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        vm.prank(alice);
        market.cancelOrder(0);

        assertEq(IERC20(UNICORN).balanceOf(alice), 9);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 5_000_000);
        assertEq(uint256(market.getOrder(0).status), uint256(UnicornMarket.OrderStatus.Cancelled));
    }

    // ════════════════════════════════════════════════════════════════
    // 2. WRAPPED PAIR: W_UNICORN ⇄ W_MEAT
    // ════════════════════════════════════════════════════════════════

    function test_wUnicornForWMeat() public {
        _seedWUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(W_UNICORN).approve(address(market), 2);
        market.placeOrder(W_UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(0, 2);
        vm.stopPrank();

        assertEq(IERC20(W_UNICORN).balanceOf(bob), 2);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 10_000_000);
    }

    function test_wMeatForWUnicorn() public {
        _seedWMeat(alice, 50_000_000);
        _seedWUnicorn(bob, 10);

        vm.startPrank(alice);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.placeOrder(W_MEAT, W_UNICORN, 10_000_000, 2);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_UNICORN).approve(address(market), 2);
        market.fillOrder(0, 10_000_000);
        vm.stopPrank();

        assertEq(IERC20(W_UNICORN).balanceOf(alice), 2);
        assertEq(IERC20(W_MEAT).balanceOf(bob), 10_000_000);
    }

    // ════════════════════════════════════════════════════════════════
    // 3. REVERT: SAME-SIDE PAIRS
    // ════════════════════════════════════════════════════════════════

    function test_revert_sameSide_unicornForWUnicorn() public {
        _seedUnicorn(alice, 5);
        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 1);
        vm.expectRevert(UnicornMarket.InvalidPair.selector);
        market.placeOrder(UNICORN, W_UNICORN, 1, 1);
        vm.stopPrank();
    }

    function test_revert_sameSide_meatForWMeat() public {
        deal(MEAT, alice, 5000, false);
        vm.startPrank(alice);
        vm.expectRevert(UnicornMarket.InvalidPair.selector);
        market.placeOrder(MEAT, W_MEAT, 1000, 1000);
        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════════════
    // 4. REVERT CASES
    // ════════════════════════════════════════════════════════════════

    function test_revert_invalidToken() public {
        address fake = makeAddr("fake");
        vm.expectRevert(UnicornMarket.InvalidToken.selector);
        market.placeOrder(fake, W_MEAT, 1, 1);
    }

    function test_revert_zeroAmount() public {
        _seedUnicorn(alice, 5);
        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 1);
        vm.expectRevert(UnicornMarket.InvalidAmount.selector);
        market.placeOrder(UNICORN, W_MEAT, 0, 1);
        vm.stopPrank();
    }

    function test_revert_fillZero() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        vm.expectRevert(UnicornMarket.InvalidAmount.selector);
        market.fillOrder(0, 0);
        vm.stopPrank();
    }

    function test_revert_overfill() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 50_000_000);
        vm.expectRevert(UnicornMarket.Overfill.selector);
        market.fillOrder(0, 3);
        vm.stopPrank();
    }

    function test_revert_fillCancelled() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        market.cancelOrder(0);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        vm.expectRevert(UnicornMarket.OrderNotOpen.selector);
        market.fillOrder(0, 2);
        vm.stopPrank();
    }

    function test_revert_cancelNotMaker() public {
        _seedUnicorn(alice, 5);
        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(UnicornMarket.NotMaker.selector);
        market.cancelOrder(0);
    }

    function test_revert_doubleFill() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(0, 2);
        vm.expectRevert(UnicornMarket.OrderNotOpen.selector);
        market.fillOrder(0, 1);
        vm.stopPrank();
    }

    function test_revert_doubleCancel() public {
        _seedUnicorn(alice, 5);
        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        market.cancelOrder(0);
        vm.expectRevert(UnicornMarket.OrderNotOpen.selector);
        market.cancelOrder(0);
        vm.stopPrank();
    }

    function test_revert_invalidOrderId() public {
        vm.expectRevert(UnicornMarket.InvalidOrder.selector);
        market.getOrder(0);

        vm.expectRevert(UnicornMarket.InvalidOrder.selector);
        market.fillOrder(99, 1);

        vm.expectRevert(UnicornMarket.InvalidOrder.selector);
        market.cancelOrder(99);
    }

    // ════════════════════════════════════════════════════════════════
    // 5. ROUNDING / DUST (Math.mulDiv with Rounding.Up)
    // ════════════════════════════════════════════════════════════════

    function test_rounding_oddRatio() public {
        _seedUnicorn(alice, 10);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 3);
        market.placeOrder(UNICORN, W_MEAT, 3, 10_000_000);
        vm.stopPrank();

        // Take 1 of 3: 10M/3 = 3,333,333.33 → rounds up to 3,333,334
        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        UnicornMarket.Order memory o = market.getOrder(0);
        assertEq(o.sellAmountRemaining, 2);
        assertEq(o.buyAmountRemaining, 6_666_666);

        // Take 1 more
        vm.startPrank(bob);
        market.fillOrder(0, 1);
        vm.stopPrank();

        o = market.getOrder(0);
        assertEq(o.sellAmountRemaining, 1);
        assertEq(o.buyAmountRemaining, 3_333_332);

        // Take last 1 — exact remaining
        vm.startPrank(bob);
        market.fillOrder(0, 1);
        vm.stopPrank();

        o = market.getOrder(0);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Filled));
        assertEq(o.sellAmountRemaining, 0);
        assertEq(o.buyAmountRemaining, 0);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 10_000_000);
    }

    // ════════════════════════════════════════════════════════════════
    // 6. VIEW: getOrderBook
    // ════════════════════════════════════════════════════════════════

    function test_getOrderBook() public {
        _seedUnicorn(alice, 10);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 6);
        market.placeOrder(UNICORN, W_MEAT, 1, 5_000_000);  // 0
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000); // 1
        market.placeOrder(UNICORN, W_MEAT, 3, 15_000_000); // 2
        market.cancelOrder(1);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        // Only order 2 should be open for UNICORN→W_MEAT
        uint256[] memory asks = market.getOrderBook(UNICORN, W_MEAT);
        assertEq(asks.length, 1);
        assertEq(asks[0], 2);
    }

    // ════════════════════════════════════════════════════════════════
    // 7. EVENTS
    // ════════════════════════════════════════════════════════════════

    function test_events_placeOrder() public {
        _seedUnicorn(alice, 5);
        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        vm.expectEmit(true, true, false, true);
        emit UnicornMarket.OrderPlaced(0, alice, UNICORN, W_MEAT, 2, 10_000_000);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();
    }

    function test_events_fillOrder() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        vm.expectEmit(true, true, false, true);
        emit UnicornMarket.OrderFilled(0, bob, 2, 10_000_000, 0, 0);
        market.fillOrder(0, 2);
        vm.stopPrank();
    }

    function test_events_cancelOrder() public {
        _seedUnicorn(alice, 5);
        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.expectEmit(true, true, false, true);
        emit UnicornMarket.OrderCancelled(0, alice, 2);
        market.cancelOrder(0);
        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════════════
    // 8. EDGE CASES
    // ════════════════════════════════════════════════════════════════

    function test_singleUnitOrder() public {
        _seedUnicorn(alice, 1);
        _seedWMeat(bob, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 1);
        market.placeOrder(UNICORN, W_MEAT, 1, 5_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        assertEq(IERC20(UNICORN).balanceOf(bob), 1);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 5_000_000);
    }

    function test_manyOrders() public {
        _seedUnicorn(alice, 100);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 100);
        for (uint256 i; i < 20; i++) {
            market.placeOrder(UNICORN, W_MEAT, 5, 25_000_000);
        }
        vm.stopPrank();

        assertEq(market.orderCount(), 20);
        uint256[] memory open = market.getOrderBook(UNICORN, W_MEAT);
        assertEq(open.length, 20);
    }

    function test_selfFill() public {
        _seedUnicorn(alice, 5);
        _seedWMeat(alice, 50_000_000);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(0, 2);
        vm.stopPrank();

        assertEq(IERC20(UNICORN).balanceOf(alice), 5);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 50_000_000);
    }
}
