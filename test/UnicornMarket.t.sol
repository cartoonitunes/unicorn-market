// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "../src/UnicornMarket.sol";

/// @dev Mock ERC20 for testing
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract UnicornMarketTest is Test {
    UnicornMarket market;

    // We deploy mock tokens at the exact addresses the contract expects
    // using vm.etch
    address constant UNICORN = 0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7;
    address constant W_UNICORN = 0x38a9aF1BD00f9988977095B31eb18d6D3D5dCA00;
    address constant MEAT = 0xED6aC8de7c7CA7e3A22952e09C2a2A1232DDef9A;
    address constant W_MEAT = 0xDFA208BB0B811cFBB5Fa3Ea98Ec37Aa86180e668;

    MockERC20 unicornMock;
    MockERC20 wUnicornMock;
    MockERC20 meatMock;
    MockERC20 wMeatMock;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // Deploy mock tokens to temp addresses then etch bytecode to expected addresses
        unicornMock = new MockERC20("Unicorns", "UNI", 0);
        wUnicornMock = new MockERC20("Wrapped Unicorn", "wUNI", 0);
        meatMock = new MockERC20("Unicorn Meat", "MEAT", 3);
        wMeatMock = new MockERC20("Wrapped Unicorn Meat", "wMEAT", 3);

        vm.etch(UNICORN, address(unicornMock).code);
        vm.etch(W_UNICORN, address(wUnicornMock).code);
        vm.etch(MEAT, address(meatMock).code);
        vm.etch(W_MEAT, address(wMeatMock).code);

        market = new UnicornMarket();

        // Mint tokens to test users
        // Alice has 10 Unicorns
        MockERC20(UNICORN).mint(alice, 10);
        // Bob has 100,000 Meat (100,000.000 with 3 decimals = 100_000_000)
        MockERC20(W_MEAT).mint(bob, 100_000_000);
    }

    // ─── Place Order ───────────────────────────────────────────────────

    function test_placeOrder() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000); // 2 unicorns for 10,000 meat
        vm.stopPrank();

        assertEq(id, 0);
        assertEq(market.orderCount(), 1);

        // Alice's unicorns escrowed
        assertEq(MockERC20(UNICORN).balanceOf(alice), 8);
        assertEq(MockERC20(UNICORN).balanceOf(address(market)), 2);
    }

    function test_placeOrder_meatForUnicorn() public {
        vm.startPrank(bob);
        MockERC20(W_MEAT).approve(address(market), 50_000_000);
        uint256 id = market.placeOrder(W_MEAT, UNICORN, 50_000_000, 5); // 50k meat for 5 unicorns
        vm.stopPrank();

        assertEq(id, 0);
        assertEq(MockERC20(W_MEAT).balanceOf(bob), 50_000_000);
        assertEq(MockERC20(W_MEAT).balanceOf(address(market)), 50_000_000);
    }

    function test_revert_sameSide() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 1);
        vm.expectRevert(UnicornMarket.InvalidPair.selector);
        market.placeOrder(UNICORN, W_UNICORN, 1, 1); // same side
        vm.stopPrank();
    }

    function test_revert_invalidToken() public {
        vm.startPrank(alice);
        vm.expectRevert(UnicornMarket.InvalidToken.selector);
        market.placeOrder(address(0xdead), W_MEAT, 1, 1);
        vm.stopPrank();
    }

    function test_revert_zeroAmount() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 1);
        vm.expectRevert(UnicornMarket.InvalidAmount.selector);
        market.placeOrder(UNICORN, W_MEAT, 0, 1000);
        vm.stopPrank();
    }

    // ─── Fill Order ────────────────────────────────────────────────────

    function test_fillOrder() public {
        // Alice places: sell 2 unicorns, want 10k meat
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        // Bob fills
        vm.startPrank(bob);
        MockERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(id);
        vm.stopPrank();

        // Alice got meat, Bob got unicorns
        assertEq(MockERC20(W_MEAT).balanceOf(alice), 10_000_000);
        assertEq(MockERC20(UNICORN).balanceOf(bob), 2);

        // Order marked filled
        (,,,,,,bool filled,) = market.getOrder(id);
        assertTrue(filled);
    }

    function test_revert_fillAlreadyFilled() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        MockERC20(W_MEAT).approve(address(market), 10_000_000);
        market.fillOrder(id);
        vm.expectRevert(UnicornMarket.OrderNotOpen.selector);
        market.fillOrder(id);
        vm.stopPrank();
    }

    // ─── Cancel Order ──────────────────────────────────────────────────

    function test_cancelOrder() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);

        // Cancel and get tokens back
        market.cancelOrder(id);
        vm.stopPrank();

        assertEq(MockERC20(UNICORN).balanceOf(alice), 10);
        (,,,,,,,bool cancelled) = market.getOrder(id);
        assertTrue(cancelled);
    }

    function test_revert_cancelNotMaker() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(UnicornMarket.NotMaker.selector);
        market.cancelOrder(id);
        vm.stopPrank();
    }

    function test_revert_fillCancelled() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 2);
        uint256 id = market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        market.cancelOrder(id);
        vm.stopPrank();

        vm.startPrank(bob);
        MockERC20(W_MEAT).approve(address(market), 10_000_000);
        vm.expectRevert(UnicornMarket.OrderNotOpen.selector);
        market.fillOrder(id);
        vm.stopPrank();
    }

    // ─── View Functions ────────────────────────────────────────────────

    function test_getOpenOrderIds() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 5);
        market.placeOrder(UNICORN, W_MEAT, 1, 5_000_000);  // id 0
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000); // id 1
        market.placeOrder(UNICORN, W_MEAT, 1, 4_000_000);  // id 2
        market.cancelOrder(1); // cancel id 1
        vm.stopPrank();

        uint256[] memory open = market.getOpenOrderIds();
        assertEq(open.length, 2);
        assertEq(open[0], 0);
        assertEq(open[1], 2);
    }

    function test_getOrdersByMaker() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 3);
        market.placeOrder(UNICORN, W_MEAT, 1, 5_000_000);
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        MockERC20(W_MEAT).approve(address(market), 50_000_000);
        market.placeOrder(W_MEAT, UNICORN, 50_000_000, 5);
        vm.stopPrank();

        uint256[] memory aliceOrders = market.getOrdersByMaker(alice);
        assertEq(aliceOrders.length, 2);

        uint256[] memory bobOrders = market.getOrdersByMaker(bob);
        assertEq(bobOrders.length, 1);
    }

    function test_getOrderBook() public {
        vm.startPrank(alice);
        MockERC20(UNICORN).approve(address(market), 3);
        market.placeOrder(UNICORN, W_MEAT, 1, 5_000_000);  // unicorn→meat
        market.placeOrder(UNICORN, W_MEAT, 2, 10_000_000); // unicorn→meat
        vm.stopPrank();

        vm.startPrank(bob);
        MockERC20(W_MEAT).approve(address(market), 50_000_000);
        market.placeOrder(W_MEAT, UNICORN, 50_000_000, 5); // meat→unicorn
        vm.stopPrank();

        uint256[] memory asks = market.getOrderBook(UNICORN, W_MEAT);
        assertEq(asks.length, 2);

        uint256[] memory bids = market.getOrderBook(W_MEAT, UNICORN);
        assertEq(bids.length, 1);
    }

    // ─── Mixed token variants ──────────────────────────────────────────

    function test_crossVariant_wrappedUnicornForOriginalMeat() public {
        MockERC20(W_UNICORN).mint(alice, 5);
        MockERC20(MEAT).mint(bob, 50_000_000);

        vm.startPrank(alice);
        MockERC20(W_UNICORN).approve(address(market), 3);
        uint256 id = market.placeOrder(W_UNICORN, MEAT, 3, 15_000_000);
        vm.stopPrank();

        vm.startPrank(bob);
        MockERC20(MEAT).approve(address(market), 15_000_000);
        market.fillOrder(id);
        vm.stopPrank();

        assertEq(MockERC20(W_UNICORN).balanceOf(bob), 3);
        assertEq(MockERC20(MEAT).balanceOf(alice), 15_000_000);
    }
}
