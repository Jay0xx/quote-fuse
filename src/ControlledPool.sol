// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IPoolToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

/// @notice Minimal 18-decimal constant-product pool for controlled testnet swaps.
contract ControlledPool {
    IPoolToken public immutable token0;
    IPoolToken public immutable token1;
    uint112 public reserve0;
    uint112 public reserve1;
    bool private entered;

    event Sync(uint112 reserve0, uint112 reserve1);
    event Swap(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut);
    error InvalidPool();
    error TransferFailed();
    error Slippage();

    constructor(IPoolToken token0_, IPoolToken token1_) {
        if (address(token0_) == address(0) || address(token1_) == address(0) || address(token0_) == address(token1_)
            || address(token0_) >= address(token1_) || address(token0_).code.length == 0 || address(token1_).code.length == 0) revert InvalidPool();
        token0 = token0_;
        token1 = token1_;
    }

    modifier nonReentrant() {
        if (entered) revert InvalidPool();
        entered = true;
        _;
        entered = false;
    }

    function seed(uint256 amount0, uint256 amount1) external nonReentrant {
        if (reserve0 != 0 || reserve1 != 0 || amount0 == 0 || amount1 == 0) revert InvalidPool();
        _pull(token0, amount0);
        _pull(token1, amount1);
        _sync();
    }

    function swapExact0For1(uint256 amountIn, uint256 minOut) external nonReentrant returns (uint256 amountOut) {
        amountOut = _swap(token0, token1, amountIn, minOut, true);
    }

    function swapExact1For0(uint256 amountIn, uint256 minOut) external nonReentrant returns (uint256 amountOut) {
        amountOut = _swap(token1, token0, amountIn, minOut, false);
    }

    function _swap(IPoolToken inToken, IPoolToken outToken, uint256 amountIn, uint256 minOut, bool zeroForOne) private returns (uint256 amountOut) {
        uint256 inReserve = zeroForOne ? reserve0 : reserve1;
        uint256 outReserve = zeroForOne ? reserve1 : reserve0;
        if (inReserve == 0 || outReserve == 0 || amountIn == 0) revert InvalidPool();
        uint256 beforeIn = inToken.balanceOf(address(this));
        _pull(inToken, amountIn);
        uint256 received = inToken.balanceOf(address(this)) - beforeIn;
        amountOut = outReserve * received / (inReserve + received);
        if (amountOut == 0 || amountOut < minOut) revert Slippage();
        if (!outToken.transfer(msg.sender, amountOut)) revert TransferFailed();
        _sync();
        emit Swap(msg.sender, address(inToken), received, amountOut);
    }

    function _pull(IPoolToken token, uint256 amount) private {
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    function _sync() private {
        uint256 b0 = token0.balanceOf(address(this));
        uint256 b1 = token1.balanceOf(address(this));
        if (b0 == 0 || b1 == 0 || b0 > type(uint112).max || b1 > type(uint112).max) revert InvalidPool();
        reserve0 = uint112(b0);
        reserve1 = uint112(b1);
        emit Sync(reserve0, reserve1);
    }
}
