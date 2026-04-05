// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/TokenA.sol";
import "../src/TokenB.sol";
import "../src/AMM.sol";
import "../src/LPToken.sol";

contract AMMTest is Test {
    TokenA tokenA;
    TokenB tokenB;
    AMM amm;
    LPToken lp;

    address user1 = address(1);
    address user2 = address(2);

    function setUp() public {
        tokenA = new TokenA();
        tokenB = new TokenB();
        amm = new AMM(address(tokenA), address(tokenB));
        lp = LPToken(address(amm.lpToken()));

        tokenA.mint(user1, 1_000_000 ether);
        tokenB.mint(user1, 1_000_000 ether);
        tokenA.mint(user2, 1_000_000 ether);
        tokenB.mint(user2, 1_000_000 ether);

        vm.startPrank(user1);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function _addInitialLiquidity() internal {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether);
    }

    function testAddLiquidityFirstProvider() public {
        vm.prank(user1);
        uint256 lpMinted = amm.addLiquidity(1000 ether, 1000 ether);

        assertGt(lpMinted, 0);
        assertEq(amm.reserveA(), 1000 ether);
        assertEq(amm.reserveB(), 1000 ether);
    }

    function testAddLiquiditySecondProvider() public {
        _addInitialLiquidity();

        vm.prank(user2);
        uint256 lpMinted = amm.addLiquidity(500 ether, 500 ether);

        assertGt(lpMinted, 0);
        assertEq(amm.reserveA(), 1500 ether);
        assertEq(amm.reserveB(), 1500 ether);
    }

    function testRevertAddLiquidityWrongRatio() public {
        _addInitialLiquidity();

        vm.prank(user2);
        vm.expectRevert("wrong ratio");
        amm.addLiquidity(100 ether, 200 ether);
    }

    function testRevertAddLiquidityZeroAmounts() public {
        vm.prank(user1);
        vm.expectRevert("zero amounts");
        amm.addLiquidity(0, 100 ether);
    }

    function testRemoveLiquidityPartial() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether);

        uint256 lpBalance = lp.balanceOf(user1);
        uint256 removeAmount = lpBalance / 2;

        vm.prank(user1);
        (uint256 amountA, uint256 amountB) = amm.removeLiquidity(removeAmount);

        assertEq(amountA, 500 ether);
        assertEq(amountB, 500 ether);
    }

    function testRemoveLiquidityFull() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether);

        uint256 lpBalance = lp.balanceOf(user1);

        vm.prank(user1);
        amm.removeLiquidity(lpBalance);

        assertEq(amm.reserveA(), 0);
        assertEq(amm.reserveB(), 0);
    }

    function testRevertRemoveLiquidityZero() public {
        vm.prank(user1);
        vm.expectRevert("zero lp");
        amm.removeLiquidity(0);
    }

    function testSwapAToB() public {
        _addInitialLiquidity();

        vm.prank(user2);
        uint256 amountOut = amm.swap(address(tokenA), 100 ether, 0);

        assertGt(amountOut, 0);
        assertGt(tokenB.balanceOf(user2), 1_000_000 ether);
    }

    function testSwapBToA() public {
        _addInitialLiquidity();

        vm.prank(user2);
        uint256 amountOut = amm.swap(address(tokenB), 100 ether, 0);

        assertGt(amountOut, 0);
        assertGt(tokenA.balanceOf(user2), 1_000_000 ether);
    }

    function testGetAmountOut() public {
        _addInitialLiquidity();

        uint256 amountOut = amm.getAmountOut(100 ether, address(tokenA));
        assertGt(amountOut, 0);
    }

    function testKDoesNotDecreaseAfterSwap() public {
        _addInitialLiquidity();

        uint256 kBefore = amm.reserveA() * amm.reserveB();

        vm.prank(user2);
        amm.swap(address(tokenA), 100 ether, 0);

        uint256 kAfter = amm.reserveA() * amm.reserveB();
        assertGe(kAfter, kBefore);
    }

    function testRevertSwapSlippage() public {
        _addInitialLiquidity();

        vm.prank(user2);
        vm.expectRevert("slippage");
        amm.swap(address(tokenA), 100 ether, 1000 ether);
    }

    function testRevertSwapZeroInput() public {
        _addInitialLiquidity();

        vm.prank(user2);
        vm.expectRevert("zero input");
        amm.swap(address(tokenA), 0, 0);
    }

    function testRevertSwapInvalidToken() public {
        _addInitialLiquidity();

        vm.prank(user2);
        vm.expectRevert("invalid token");
        amm.swap(address(999), 100 ether, 0);
    }

    function testLargeSwapHighPriceImpact() public {
        _addInitialLiquidity();

        uint256 outSmall = amm.getAmountOut(10 ether, address(tokenA));
        uint256 outLarge = amm.getAmountOut(500 ether, address(tokenA));

        assertLt(outLarge / 500, outSmall / 10);
    }

    function testSingleSidedLiquidityFails() public {
        vm.prank(user1);
        vm.expectRevert("zero amounts");
        amm.addLiquidity(100 ether, 0);
    }

    function testLPTokenMintedToProvider() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether);

        assertGt(lp.balanceOf(user1), 0);
    }

    function testFuzzSwap(uint256 amountIn) public {
        _addInitialLiquidity();

        amountIn = bound(amountIn, 1 ether, 100 ether);

        vm.prank(user2);
        uint256 out = amm.swap(address(tokenA), amountIn, 0);

        assertGt(out, 0);
    }
}