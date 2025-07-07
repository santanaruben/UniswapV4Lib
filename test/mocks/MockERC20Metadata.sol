// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockERC20Metadata is IERC20Metadata {
    string public name_;
    string public symbol_;
    uint8 public decimals_;
    uint256 public totalSupply_;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name_ = _name;
        symbol_ = _symbol;
        decimals_ = _decimals;
    }

    function name() external view override returns (string memory) {
        return name_;
    }

    function symbol() external view override returns (string memory) {
        return symbol_;
    }

    function decimals() external view override returns (uint8) {
        return decimals_;
    }

    function totalSupply() external view override returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balances[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        require(allowances[from][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // Funciones para facilitar el testing
    function mint(address account, uint256 amount) public {
        totalSupply_ += amount;
        balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _setDecimals(uint8 newDecimals) public {
        decimals_ = newDecimals;
    }
} 