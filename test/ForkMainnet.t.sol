// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract ForkMainnetTest is Test {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function setUp() public {
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
    }

    function testReadUSDCTotalSupply() public view {
        uint256 supply = IERC20(USDC).totalSupply();
        console2.log("USDC total supply:", supply);
        assertGt(supply, 0);
    }

    function testUniswapV2SwapETHToUSDC() public {
        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = USDC;

        vm.deal(address(this), 1 ether);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(this));

        router.swapExactETHForTokens{value: 0.1 ether}(
            0,
            path,
            address(this),
            block.timestamp + 300
        );

        uint256 afterBal = IERC20(USDC).balanceOf(address(this));

        console2.log("USDC before swap:", beforeBal);
        console2.log("USDC after swap:", afterBal);

        assertGt(afterBal, beforeBal);
    }

    function testForkRoll() public {
    uint256 b = block.number;
    console2.log("Current fork block:", b);

    vm.rollFork(b - 1);

    uint256 newBlock = block.number;
    console2.log("New fork block:", newBlock);

    assertEq(newBlock, b - 1);
}
}
