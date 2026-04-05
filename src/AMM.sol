// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BaseERC20.sol";
import "./LPToken.sol";

contract AMM {
    BaseERC20 public tokenA;
    BaseERC20 public tokenB;
    LPToken public lpToken;

    uint256 public reserveA;
    uint256 public reserveB;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Swap(address indexed user, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);

    constructor(address _tokenA, address _tokenB) {
        require(_tokenA != _tokenB, "same token");
        tokenA = BaseERC20(_tokenA);
        tokenB = BaseERC20(_tokenB);
        lpToken = new LPToken();
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _updateReserves() internal {
        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external returns (uint256 lpMinted) {
        require(amountA > 0 && amountB > 0, "zero amounts");

        if (reserveA > 0 || reserveB > 0) {
            require(reserveA * amountB == reserveB * amountA, "wrong ratio");
        }

        require(tokenA.transferFrom(msg.sender, address(this), amountA), "transfer A failed");
        require(tokenB.transferFrom(msg.sender, address(this), amountB), "transfer B failed");

        uint256 totalLP = lpToken.totalSupply();

        if (totalLP == 0) {
            lpMinted = sqrt(amountA * amountB);
        } else {
            lpMinted = min(
                (amountA * totalLP) / reserveA,
                (amountB * totalLP) / reserveB
            );
        }

        require(lpMinted > 0, "lp zero");

        lpToken.mint(msg.sender, lpMinted);
        _updateReserves();

        emit LiquidityAdded(msg.sender, amountA, amountB, lpMinted);
    }

    function removeLiquidity(uint256 lpAmount) external returns (uint256 amountA, uint256 amountB) {
        require(lpAmount > 0, "zero lp");

        uint256 totalLP = lpToken.totalSupply();
        require(totalLP > 0, "no lp supply");

        amountA = (lpAmount * reserveA) / totalLP;
        amountB = (lpAmount * reserveB) / totalLP;

        require(amountA > 0 && amountB > 0, "zero output");

        lpToken.burn(msg.sender, lpAmount);

        require(tokenA.transfer(msg.sender, amountA), "transfer A failed");
        require(tokenB.transfer(msg.sender, amountB), "transfer B failed");

        _updateReserves();

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
        require(amountIn > 0, "zero input");

        bool isTokenAIn = tokenIn == address(tokenA);
        require(isTokenAIn || tokenIn == address(tokenB), "invalid token");

        uint256 reserveIn = isTokenAIn ? reserveA : reserveB;
        uint256 reserveOut = isTokenAIn ? reserveB : reserveA;

        require(reserveIn > 0 && reserveOut > 0, "no liquidity");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;

        amountOut = numerator / denominator;
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        require(amountIn > 0, "zero input");
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "invalid token");

        bool isTokenAIn = tokenIn == address(tokenA);

        BaseERC20 inToken = isTokenAIn ? tokenA : tokenB;
        BaseERC20 outToken = isTokenAIn ? tokenB : tokenA;

        amountOut = getAmountOut(amountIn, tokenIn);
        require(amountOut >= minAmountOut, "slippage");

        require(inToken.transferFrom(msg.sender, address(this), amountIn), "transfer in failed");
        require(outToken.transfer(msg.sender, amountOut), "transfer out failed");

        _updateReserves();

        emit Swap(msg.sender, address(inToken), amountIn, address(outToken), amountOut);
    }

    function getK() external view returns (uint256) {
        return reserveA * reserveB;
    }
}