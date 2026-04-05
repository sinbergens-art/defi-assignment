// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BaseERC20.sol";

contract LPToken is BaseERC20 {
    address public amm;

    constructor() BaseERC20("LP Token", "LPT") {
        amm = msg.sender;
    }

    modifier onlyAMM() {
        require(msg.sender == amm, "only amm");
        _;
    }

    function mint(address to, uint256 amount) external onlyAMM {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyAMM {
        _burn(from, amount);
    }
}