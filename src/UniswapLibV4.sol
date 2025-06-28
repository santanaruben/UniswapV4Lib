// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {AddressConstants} from "./AddressConstants.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

// import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
// import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

library UniswapLibV4 {
    
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    uint24 public constant FEE = 500; // 0.05%
    int24 public constant TICK_SPACING = 60;
	IHooks constant HOOK_CONTRACT = IHooks(address(0x0)); // hook address

    /// @dev Swaps ERC20 whitelisted tokens for ETH using Uniswap V4.
    /// @param poolManager uniswap v4 poolManager.
    /// @param swapRouter uniswap v4 swapRouter.
    /// @param tokenAddress Address of the ERC20 token to be swapped.
    /// @param _OZW Address of the openzeppelin defender.
    function _swapTokensForETH(
        IPoolManager poolManager,
        IUniswapV4Router04 swapRouter,
        address tokenAddress,
        address _OZW
    ) public returns(BalanceDelta swapDelta){

        // IPoolManager POOLMANAGER = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        IPoolManager POOLMANAGER = poolManager;
        // IUniswapV4Router04 SWAPROUTER = IUniswapV4Router04(payable(AddressConstants.getV4SwapRouterAddress(block.chainid)));
        IUniswapV4Router04 SWAPROUTER = swapRouter;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(tokenAddress),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOK_CONTRACT
        });
        IERC20Metadata _asset = IERC20Metadata(tokenAddress);
        uint256 assetsDecimals = 5 * 10 ** IERC20Metadata(_asset).decimals(); // Deduct 5 tokens for Minimal Floor of Vault
        // address OZW = AddressConstants.getOZWAddress(block.chainid);
        address OZW = _OZW;

        uint256 tokenAmount = IERC20Metadata(_asset).balanceOf(OZW) - assetsDecimals; // Deduct 5 token fee

        uint256 expectedAmount = FullMath.mulDiv(tokenAmount,
            getPriceInPaymentToken(POOLMANAGER, address(_asset)),
            10 ** IERC20Metadata(_asset).decimals()
        );

        // transfer and allowances

        IERC20(tokenAddress).safeTransferFrom(
            address(OZW),
            address(this),
            tokenAmount
        );

        uint256 currentAllowance = IERC20Metadata(tokenAddress).allowance(
            address(this),
            address(SWAPROUTER)
        );

        if (currentAllowance < tokenAmount) {
            IERC20(tokenAddress).safeIncreaseAllowance(
                address(SWAPROUTER),
                tokenAmount - currentAllowance
            );
        }

        uint256 amountOutMinimum = FullMath.mulDiv(expectedAmount, 950, 1000); // 5% slippage

        swapDelta = SWAPROUTER.swapExactTokensForTokens({
            amountIn: tokenAmount,
            amountOutMin: amountOutMinimum,
            zeroForOne: false,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1800
        });

        uint256 amountOut = uint256(uint128(swapDelta.amount0()));

        // Verify the output amount
        require(amountOut >= amountOutMinimum, "Insufficient output amount");

        // Securely transfer ETH to OpenZeppelin Defender Wallet
        // (bool success, ) = OZW.call{value: address(this).balance}("");
        (bool success, ) = OZW.call{value: amountOut}("");
        require(success, "Tx failed");
    }

    /// @dev Retrieves the price of 1 token in terms of the payment token using a Uniswap V4 pool.
    /// @param poolManager uniswap v4 poolManager.
    /// @param tokenAddress Address of the ERC20 token to get the price for.
    /// @return price Price of the token in the payment token, adjusted in wei format.
    function getPriceInPaymentToken(IPoolManager poolManager, address tokenAddress) public view returns (uint256 price) {
        require(tokenAddress != address(0), "Token cannot be zero address");

        // IPoolManager POOLMANAGER = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        IPoolManager POOLMANAGER = poolManager;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(tokenAddress),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOK_CONTRACT
        });

        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = POOLMANAGER.getSlot0(poolId);

        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), sqrtPriceX96, 1);

        uint256 decimalsToken = 10 ** IERC20Metadata(tokenAddress).decimals();
        uint256 decimalsETH = 10 ** 18;

        uint256 raw_price_inverted_scaled = FullMath.mulDiv(2**192, 10**18, priceX96);
        // Calculates the price of the token in ETH, adjusted by the decimal places of the token and ETH, and scaled to 18 decimal places. (wei format)

        price = FullMath.mulDiv(raw_price_inverted_scaled, decimalsToken, decimalsETH);
    }

    // /// @dev Retrieves the price of an amount of tokens in terms of ETH using a Uniswap V4 pool.
    // /// @param poolManager uniswap v4 poolManager.
    // /// @param tokenAddress Address of the ERC20 token to get the price for.
    // /// @param amountIn Amount ERC20 token to get the price for.
    // /// @return amountOut Price of the tokens in ETH, adjusted in wei format.
    // function computePrice(IPoolManager poolManager, address tokenAddress, uint256 amountIn) public view returns(uint256 amountOut) {
    //     IPoolManager POOLMANAGER = poolManager;

    //     PoolKey memory poolKey = PoolKey({
    //         currency0: Currency.wrap(address(0)),
    //         currency1: Currency.wrap(tokenAddress),
    //         fee: FEE,
    //         tickSpacing: TICK_SPACING,
    //         hooks: HOOK_CONTRACT
    //     });

    //     PoolId poolId = poolKey.toId();
    //     (uint160 sqrtPriceX96,,,) = POOLMANAGER.getSlot0(poolId);

    //     (,uint256 amount0Delta,,) = SwapMath.computeSwapStep(
    //         sqrtPriceX96,
    //         TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK), // Swap hasta el final (simplificado)
    //         POOLMANAGER.getLiquidity(poolId),
    //         int256(amountIn),
    //         FEE
    //     );
    //     amountOut = amount0Delta;
    // }
}