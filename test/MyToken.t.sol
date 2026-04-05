// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken token;
    address user = address(1);

    function setUp() public {
        token = new MyToken();
        token.mint(user, 1000 ether);
    }

    function testMint() public {
        token.mint(address(this), 500 ether);
        assertEq(token.balanceOf(address(this)), 500 ether);
    }

    function testTransfer() public {
        vm.prank(user);
        token.transfer(address(this), 100 ether);
        assertEq(token.balanceOf(address(this)), 100 ether);
    }

    function testApprove() public {
        vm.prank(user);
        token.approve(address(this), 200 ether);
        assertEq(token.allowance(user, address(this)), 200 ether);
    }

    function testTransferFrom() public {
        vm.startPrank(user);
        token.approve(address(this), 100 ether);
        vm.stopPrank();

        token.transferFrom(user, address(this), 100 ether);
        assertEq(token.balanceOf(address(this)), 100 ether);
    }

    function test_RevertWhen_TransferTooMuch() public {
        vm.prank(user);
        vm.expectRevert("Not enough balance");
        token.transfer(address(this), 2000 ether);
    }

    function testTransferUpdatesBalances() public {
        vm.prank(user);
        token.transfer(address(this), 50 ether);

        assertEq(token.balanceOf(user), 950 ether);
        assertEq(token.balanceOf(address(this)), 50 ether);
    }

    function testAllowanceDecrease() public {
        vm.startPrank(user);
        token.approve(address(this), 100 ether);
        vm.stopPrank();

        token.transferFrom(user, address(this), 60 ether);

        assertEq(token.allowance(user, address(this)), 40 ether);
    }

    function testMultipleTransfers() public {
        vm.prank(user);
        token.transfer(address(this), 100 ether);

        vm.prank(user);
        token.transfer(address(this), 200 ether);

        assertEq(token.balanceOf(address(this)), 300 ether);
    }

    function testTotalSupply() public view {
        assertEq(token.totalSupply(), 1000 ether);
    }

    function testFuzzTransfer(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.prank(user);
        token.transfer(address(this), amount);

        assertEq(token.balanceOf(address(this)), amount);
    }
}