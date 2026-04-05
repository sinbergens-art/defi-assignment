// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract LendingPool {
    IERC20Minimal public immutable token;
    address public owner;

    uint256 public constant LTV = 75; // 75%
    uint256 public constant LIQUIDATION_BONUS = 10; // 10%
    uint256 public constant PRECISION = 1e18;
    uint256 public constant YEAR = 365 days;

    // annual simple linear rate, e.g. 10% = 0.10e18
    uint256 public annualInterestRate = 10e16;

    // token price in USD, 1e18 precision
    uint256 public tokenPrice = 1e18;

    struct Position {
        uint256 deposited;
        uint256 borrowed;
        uint256 lastAccrued;
    }

    mapping(address => Position) public positions;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Liquidated(address indexed liquidator, address indexed user, uint256 repaidAmount, uint256 collateralSeized);
    event PriceUpdated(uint256 newPrice);
    event InterestRateUpdated(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _token) {
        token = IERC20Minimal(_token);
        owner = msg.sender;
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "zero price");
        tokenPrice = newPrice;
        emit PriceUpdated(newPrice);
    }

    function setAnnualInterestRate(uint256 newRate) external onlyOwner {
        annualInterestRate = newRate;
        emit InterestRateUpdated(newRate);
    }

    function accrueInterest(address user) public {
        Position storage p = positions[user];

        if (p.lastAccrued == 0) {
            p.lastAccrued = block.timestamp;
            return;
        }

        if (p.borrowed == 0) {
            p.lastAccrued = block.timestamp;
            return;
        }

        uint256 dt = block.timestamp - p.lastAccrued;
        if (dt == 0) return;

        uint256 interest = (p.borrowed * annualInterestRate * dt) / (PRECISION * YEAR);
        p.borrowed += interest;
        p.lastAccrued = block.timestamp;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "zero amount");

        accrueInterest(msg.sender);

        Position storage p = positions[msg.sender];
        require(token.transferFrom(msg.sender, address(this), amount), "transfer failed");

        p.deposited += amount;
        if (p.lastAccrued == 0) {
            p.lastAccrued = block.timestamp;
        }

        emit Deposited(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "zero amount");

        accrueInterest(msg.sender);

        Position storage p = positions[msg.sender];
        require(p.deposited > 0, "no collateral");

        uint256 maxBorrow = getMaxBorrow(msg.sender);
        require(p.borrowed + amount <= maxBorrow, "ltv exceeded");
        require(token.balanceOf(address(this)) >= amount, "pool insufficient");

        p.borrowed += amount;
        require(token.transfer(msg.sender, amount), "transfer failed");

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(amount > 0, "zero amount");

        accrueInterest(msg.sender);

        Position storage p = positions[msg.sender];
        require(p.borrowed > 0, "no debt");

        uint256 repayAmount = amount > p.borrowed ? p.borrowed : amount;

        require(token.transferFrom(msg.sender, address(this), repayAmount), "transfer failed");
        p.borrowed -= repayAmount;

        emit Repaid(msg.sender, repayAmount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "zero amount");

        accrueInterest(msg.sender);

        Position storage p = positions[msg.sender];
        require(p.deposited >= amount, "not enough collateral");

        p.deposited -= amount;

        require(getHealthFactor(msg.sender) > PRECISION || p.borrowed == 0, "health factor too low");

        require(token.transfer(msg.sender, amount), "transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    function liquidate(address user, uint256 repayAmount) external {
        require(repayAmount > 0, "zero amount");

        accrueInterest(user);

        Position storage p = positions[user];
        require(p.borrowed > 0, "no debt");
        require(getHealthFactor(user) < PRECISION, "position healthy");

        uint256 actualRepay = repayAmount > p.borrowed ? p.borrowed : repayAmount;

        require(token.transferFrom(msg.sender, address(this), actualRepay), "transfer failed");

        uint256 seizeAmount = (actualRepay * (100 + LIQUIDATION_BONUS)) / 100;
        if (seizeAmount > p.deposited) {
            seizeAmount = p.deposited;
        }

        p.borrowed -= actualRepay;
        p.deposited -= seizeAmount;

        require(token.transfer(msg.sender, seizeAmount), "seize transfer failed");

        emit Liquidated(msg.sender, user, actualRepay, seizeAmount);
    }

    function getCollateralValue(address user) public view returns (uint256) {
        return (positions[user].deposited * tokenPrice) / PRECISION;
    }

    function getBorrowValue(address user) public view returns (uint256) {
        return (positions[user].borrowed * tokenPrice) / PRECISION;
    }

    function getMaxBorrow(address user) public view returns (uint256) {
        uint256 collateralValue = getCollateralValue(user);
        uint256 maxBorrowValue = (collateralValue * LTV) / 100;
        return (maxBorrowValue * PRECISION) / tokenPrice;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        Position memory p = positions[user];
        if (p.borrowed == 0) return type(uint256).max;

        uint256 collateralValue = (p.deposited * tokenPrice) / PRECISION;
        uint256 debtValue = (p.borrowed * tokenPrice) / PRECISION;

        uint256 adjustedCollateral = (collateralValue * LTV) / 100;
        return (adjustedCollateral * PRECISION) / debtValue;
    }

    function getPosition(address user) external view returns (uint256 deposited, uint256 borrowed, uint256 healthFactor) {
        deposited = positions[user].deposited;
        borrowed = positions[user].borrowed;
        healthFactor = getHealthFactor(user);
    }
}