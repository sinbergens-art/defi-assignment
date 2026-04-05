// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BaseERC20.sol";

contract TokenA is BaseERC20 {
    constructor() BaseERC20("TokenA", "TKA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}