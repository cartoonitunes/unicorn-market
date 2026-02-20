// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "../src/UnicornMarket.sol";

/// @notice Mainnet-fork tests only: uses exact deployed token contracts (no mocks/etching).
contract UnicornMarketTest is Test {
    UnicornMarket market;

    address constant UNICORN = 0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7;
    address constant W_UNICORN = 0x38a9aF1BD00f9988977095B31eb18d6D3D5dCA00;
    address constant MEAT = 0xED6aC8de7c7CA7e3A22952e09C2a2A1232DDef9A;
    address constant W_MEAT = 0xDFA208BB0B811cFBB5Fa3Ea98Ec37Aa86180e668;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc);

        // Sanity: ensure we're testing against real deployed contracts.
        assertGt(UNICORN.code.length, 0, "UNICORN code missing on fork");
        assertGt(W_UNICORN.code.length, 0, "W_UNICORN code missing on fork");
        assertGt(MEAT.code.length, 0, "MEAT code missing on fork");
        assertGt(W_MEAT.code.length, 0, "W_MEAT code missing on fork");

        market = new UnicornMarket();

        // Seed test accounts directly on fork state.
        deal(W_UNICORN, alice, 10, false);        // 10 wrapped unicorns (0 decimals)
        deal(W_MEAT, bob, 100_000_000, false);    // 100,000.000 wMEAT (3 decimals)
    }

    function _placeAliceAsk() internal returns (uint256) {
        vm.startPrank(alice);
        IERC20(W_UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(W_UNICORN, W_MEAT, 2, 10_000_000); // 2 wUNI for 10,000 wMEAT
        vm.stopPrank();
        return id;
    }

    function test_placeOrder() public {
        uint256 id = _placeAliceAsk();
        assertEq(id, 0);
        assertEq(market.orderCount(), 1);
        assertEq(IERC20(W_UNICORN).balanceOf(alice), 8);
        assertEq(IERC20(W_UNICORN).balanceOf(address(market)), 2);
    }

    function test_placeOrder_meatForUnicorn() public {
        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 50_000_000);
        uint256 id = market.placeOrder(W_MEAT, W_UNICORN, 50_000_000, 5);
        vm.stopPrank();

        assertEq(id, 0);
        assertEq(IERC20(W_MEAT).balanceOf(bob), 50_000_000);
        assertEq(IERC20(W_MEAT).balanceOf(address(market)), 50_000_000);
    }

    function test_partialFill() public {
        uint256 id = _placeAliceAsk(); // 2 UNI for 10,000 wMEAT

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(id, 1); // take 1 UNI
        vm.stopPrank();

        UnicornMarket.Order memory o = market.getOrder(id);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Open));
        assertEq(o.sellAmountRemaining, 1);
        assertEq(o.buyAmountRemaining, 5_000_000);

        assertEq(IERC20(W_UNICORN).balanceOf(bob), 1);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 5_000_000);
    }

    function test_fullFill_afterPartial() public {
        uint256 id = _placeAliceAsk();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(id, 1);
        market.fillOrder(id, 1);
        vm.stopPrank();

        UnicornMarket.Order memory o = market.getOrder(id);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Filled));
        assertEq(o.sellAmountRemaining, 0);
        assertEq(o.buyAmountRemaining, 0);

        assertEq(IERC20(W_UNICORN).balanceOf(bob), 2);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 10_000_000);
    }

    function test_revert_fillOverRemaining() public {
        uint256 id = _placeAliceAsk();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        vm.expectRevert(UnicornMarket.Overfill.selector);
        market.fillOrder(id, 3);
        vm.stopPrank();
    }

    function test_cancelAfterPartial_refundsRemainingOnly() public {
        uint256 id = _placeAliceAsk();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(id, 1);
        vm.stopPrank();

        vm.startPrank(alice);
        market.cancelOrder(id);
        vm.stopPrank();

        UnicornMarket.Order memory o = market.getOrder(id);
        assertEq(uint256(o.status), uint256(UnicornMarket.OrderStatus.Cancelled));

        // Alice started with 10 wUNI, escrowed 2, sold 1, got 1 back on cancel => 9
        assertEq(IERC20(W_UNICORN).balanceOf(alice), 9);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 5_000_000);
    }

    function test_revert_sameSide() public {
        vm.startPrank(alice);
        IERC20(W_UNICORN).approve(address(market), 1);
        vm.expectRevert(UnicornMarket.InvalidPair.selector);
        market.placeOrder(W_UNICORN, UNICORN, 1, 1);
        vm.stopPrank();
    }

    function test_getOpenOrderIds_filtersFilledAndCancelled() public {
        vm.startPrank(alice);
        IERC20(W_UNICORN).approve(address(market), 4);
        market.placeOrder(W_UNICORN, W_MEAT, 1, 5_000_000); // 0
        market.placeOrder(W_UNICORN, W_MEAT, 1, 5_000_000); // 1
        market.placeOrder(W_UNICORN, W_MEAT, 2, 10_000_000); // 2
        market.cancelOrder(1);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 5_000_000);
        market.fillOrder(0, 1);
        vm.stopPrank();

        uint256[] memory open = market.getOpenOrderIds();
        assertEq(open.length, 1);
        assertEq(open[0], 2);
    }

    function test_pair_wrappedUnicornForWrappedMeat() public {
        deal(W_UNICORN, alice, 5, false);
        deal(W_MEAT, bob, 50_000_000, false);

        vm.startPrank(alice);
        IERC20(W_UNICORN).approve(address(market), 3);
        uint256 id = market.placeOrder(W_UNICORN, W_MEAT, 3, 15_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 15_000_000);
        market.fillOrder(id, 3);
        vm.stopPrank();

        assertEq(IERC20(W_UNICORN).balanceOf(bob), 3);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 15_000_000);
    }

    function test_pair_unwrappedUnicornForWrappedMeat_legacyTokenBehavior() public {
        // Uses the exact legacy Unicorn contract on fork.
        deal(UNICORN, alice, 3, false);
        deal(W_MEAT, bob, 20_000_000, false);

        vm.startPrank(alice);
        IERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(id, 2);
        vm.stopPrank();

        assertEq(IERC20(UNICORN).balanceOf(bob), 2);
        assertEq(IERC20(W_MEAT).balanceOf(alice), 10_000_000);
    }

}
