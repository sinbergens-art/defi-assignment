// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/MockERC20.sol";
import "../src/LendingPool.sol";

contract LendingPoolTest is Test {
    MockERC20 token;
    LendingPool pool;

    address user1 = address(1);
    address user2 = address(2);
    address liquidator = address(3);

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK");
        pool = new LendingPool(address(token));

        token.mint(user1, 10_000 ether);
        token.mint(user2, 10_000 ether);
        token.mint(liquidator, 10_000 ether);

        // pool liquidity for borrowing
        token.mint(address(this), 20_000 ether);
        token.approve(address(pool), type(uint256).max);
        pool.deposit(20_000 ether);

        vm.startPrank(user1);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.prank(user1);
        pool.deposit(1000 ether);

        (uint256 deposited,,) = pool.getPosition(user1);
        assertEq(deposited, 1000 ether);
    }

    function testWithdrawWithoutDebt() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.withdraw(400 ether);
        vm.stopPrank();

        (uint256 deposited,,) = pool.getPosition(user1);
        assertEq(deposited, 600 ether);
    }

    function testBorrowWithinLTV() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(700 ether);
        vm.stopPrank();

        (,uint256 borrowed,) = pool.getPosition(user1);
        assertEq(borrowed, 700 ether);
    }

    function testRevertBorrowExceedLTV() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        vm.expectRevert("ltv exceeded");
        pool.borrow(800 ether);
        vm.stopPrank();
    }

    function testRevertBorrowWithoutCollateral() public {
        vm.prank(user1);
        vm.expectRevert("no collateral");
        pool.borrow(100 ether);
    }

    function testRepayPartial() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(600 ether);
        pool.repay(200 ether);
        vm.stopPrank();

        (,uint256 borrowed,) = pool.getPosition(user1);
        assertEq(borrowed, 400 ether);
    }

    function testRepayFull() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(600 ether);
        pool.repay(600 ether);
        vm.stopPrank();

        (,uint256 borrowed,) = pool.getPosition(user1);
        assertEq(borrowed, 0);
    }

    function testWithdrawAfterRepay() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        pool.repay(500 ether);
        pool.withdraw(1000 ether);
        vm.stopPrank();

        (uint256 deposited,uint256 borrowed,) = pool.getPosition(user1);
        assertEq(deposited, 0);
        assertEq(borrowed, 0);
    }

    function testRevertWithdrawWithUnsafeHealthFactor() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(700 ether);

        vm.expectRevert("health factor too low");
        pool.withdraw(100 ether);
        vm.stopPrank();
    }

    function testHealthFactorAfterBorrow() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        vm.stopPrank();

        (,,uint256 hf) = pool.getPosition(user1);
        assertGt(hf, 1e18);
    }

    function testInterestAccrualOverTime() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(1000 ether * 75 / 100);

        vm.warp(block.timestamp + 365 days);
        pool.repay(1 ether); // trigger accrual
        vm.stopPrank();

        (,uint256 borrowed,) = pool.getPosition(user1);
        assertGt(borrowed, 749 ether);
    }

    function testLiquidationAfterInterestAccrual() public {
    vm.startPrank(user1);
    pool.deposit(1000 ether);
    pool.borrow(740 ether);
    vm.stopPrank();

    // make interest very high for testing
    pool.setAnnualInterestRate(1e18); // 100% annual

    // move time forward so debt grows
    vm.warp(block.timestamp + 365 days);

    // trigger accrual
    vm.prank(user1);
    pool.repay(1 ether);

    (,uint256 borrowedBefore,) = pool.getPosition(user1);
    assertGt(borrowedBefore, 740 ether);

    (,,uint256 hfBefore) = pool.getPosition(user1);
    assertLt(hfBefore, 1e18);

    vm.prank(liquidator);
    pool.liquidate(user1, 300 ether);

    (,uint256 borrowedAfter,) = pool.getPosition(user1);

    assertLt(borrowedAfter, borrowedBefore);
    assertGt(token.balanceOf(liquidator), 10_000 ether);
}

    function testRevertLiquidateHealthyPosition() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        vm.stopPrank();

        vm.prank(liquidator);
        vm.expectRevert("position healthy");
        pool.liquidate(user1, 100 ether);
    }

    function testGetMaxBorrow() public {
        vm.prank(user1);
        pool.deposit(1000 ether);

        uint256 maxBorrow = pool.getMaxBorrow(user1);
        assertEq(maxBorrow, 750 ether);
    }

    function testGetPosition() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(300 ether);
        vm.stopPrank();

        (uint256 deposited, uint256 borrowed, uint256 hf) = pool.getPosition(user1);
        assertEq(deposited, 1000 ether);
        assertEq(borrowed, 300 ether);
        assertGt(hf, 1e18);
    }
}