// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BaseERC20.sol";

contract TokenB is BaseERC20 {
    constructor() BaseERC20("TokenB", "TKB") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}