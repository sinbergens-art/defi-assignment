// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../src/MyToken.sol";

contract Handler is Test {
    MyToken public token;
    address public user1 = address(1);
    address public user2 = address(2);

    constructor(MyToken _token) {
        token = _token;

        token.mint(user1, 500 ether);
        token.mint(user2, 500 ether);
    }

    function transferFromUser1(uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(user1));

        vm.prank(user1);
        token.transfer(user2, amount);
    }

    function transferFromUser2(uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(user2));

        vm.prank(user2);
        token.transfer(user1, amount);
    }

    function approveFromUser1(uint256 amount) public {
        vm.prank(user1);
        token.approve(user2, amount);
    }

    function approveFromUser2(uint256 amount) public {
        vm.prank(user2);
        token.approve(user1, amount);
    }

    function transferFromUsingAllowance(uint256 amount) public {
        uint256 allowanceAmount = token.allowance(user1, user2);
        uint256 balanceAmount = token.balanceOf(user1);

        uint256 maxAmount = allowanceAmount < balanceAmount ? allowanceAmount : balanceAmount;
        amount = bound(amount, 0, maxAmount);

        vm.prank(user2);
        token.transferFrom(user1, user2, amount);
    }
}

contract InvariantTest is StdInvariant, Test {
    MyToken token;
    Handler handler;
    uint256 initialSupply;

    function setUp() public {
        token = new MyToken();
        handler = new Handler(token);

        initialSupply = token.totalSupply();

        targetContract(address(handler));
    }

    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), initialSupply);
    }

    function invariant_noAddressHasMoreThanTotalSupply() public view {
        assertLe(token.balanceOf(address(1)), token.totalSupply());
        assertLe(token.balanceOf(address(2)), token.totalSupply());
    }
}