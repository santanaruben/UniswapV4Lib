// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Errors.sol";
import "./IRouter.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @custom:oz-upgrades-unsafe-allow external-library-linking
library UniswapLibV3 {
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    uint256 private constant TWAP_INTERVAL = 60 * 15; // 15 minutes twap;
    address public constant OZW = address(0xc6B04026Ad05981840aD6bD77c924c67bAeCf0DC); // OpenZeppelin Defender Wallet Unit-test Arbitrum Mainnet
    // address public constant OZW = address(0xdd7257d94d0F269A598FB650d331406de5A46b11); // OpenZeppelin Defender Wallet Base Mainnet
    // address public constant OZW = address(0xB8df119948e3bb1cf2255EBAfc4b9CE35b11CA22); // OpenZeppelin Defender Wallet Arbitrum Mainnet
    // address public constant OZW = address(0x60153ec0A8151f11f8c0b32D069782bf0D366a3A); // OpenZeppelin Defender Wallet Arbitrum Testnet USDc
    // address public constant OZW = address(0xf196194986C39624143cD29B4864ef3C85c35542); // OpenZeppelin Defender Wallet Arbitrum Testnet BTC
    // address public constant OZW = address(0x0931D0553329b88792a7FA0F19676B5961106ACc); // OpenZeppelin Defender Wallet Mantle Sepolia
    /// @dev Retrieves the price of 1 token in terms of the payment token using a Uniswap V3 pool.
    /// @param tokenAddress Address of the ERC20 token to get the price for.
    /// @param routerAddress Address of the Uniswap V3 router.
    /// @return price Price of the token in the payment token, adjusted for decimals.
    function getPriceInPaymentToken(
        address tokenAddress,
        address routerAddress
    ) public view returns (uint256 price) {
        IRouter router = IRouter(routerAddress);
        if (tokenAddress == address(router.WETH9())) return 1;
        IUniFactory factory = IUniFactory(router.factory());
        IUniPool pool;
        pool = IUniPool(
            factory.getPool(tokenAddress, address(router.WETH9()), 500)
        );

        if (address(pool) == address(0)) {
            pool = IUniPool(
                factory.getPool(address(router.WETH9()), tokenAddress, 500)
            );
            if (address(pool) == address(0)) revert Errors.NotZeroAddress();
        }

        address poolToken0 = pool.token0();
        address poolToken1 = pool.token1();

        bool invertPrice;

        if (
            poolToken0 == tokenAddress && poolToken1 == address(router.WETH9())
        ) {
            invertPrice = false;
        } else if (
            poolToken0 == address(router.WETH9()) && poolToken1 == tokenAddress
        ) {
            invertPrice = true;
        } else {
            revert Errors.WrongUniswapConfig();
        }

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(TWAP_INTERVAL);
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 tick = int24(tickCumulativesDelta / int56(int256(TWAP_INTERVAL)));

        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % int256(TWAP_INTERVAL) != 0)
        ) {
            tick--;
        }

        uint256 baseAmount = 10 **
            IERC20MetadataUpgradeable(tokenAddress).decimals();

        price = uint256(
            _getQuoteAtTick(
                tick,
                baseAmount,
                tokenAddress,
                address(router.WETH9())
            )
        );
    }

    /// @dev Swaps ERC20 whitelisted tokens for ETH using Uniswap V3.
    /// @param tokenAddress Address of the ERC20 token to be swapped.
    /// @param routerAddress Address of the Uniswap V3 router.
    function _swapTokensForETH(
        address tokenAddress,
        address routerAddress
    ) public {
        IRouter router = IRouter(routerAddress);
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(
            tokenAddress
        );
        uint256 assetsDecimals = 5 * 10 ** _asset.decimals(); // Deduct 5 USDc for Minimal Floor of Vault
        uint256 tokenAmount = _asset.balanceOf(OZW) - assetsDecimals; // Deduct 1 USDc fee for Vertex Protocol
        uint256 expectedAmount = tokenAmount.mulDiv(
            getPriceInPaymentToken(address(_asset), address(router)),
            assetsDecimals
        );
        SafeERC20Upgradeable.safeTransferFrom(
            _asset,
            address(OZW),
            address(this),
            tokenAmount
        );
        uint256 currentAllowance = IERC20(tokenAddress).allowance(
            address(this),
            address(router)
        );
        if (currentAllowance <= tokenAmount) {
            SafeERC20Upgradeable.safeIncreaseAllowance(
                IERC20MetadataUpgradeable(tokenAddress),
                address(router),
                tokenAmount - currentAllowance
            );
        }

        IRouter.ExactInputSingleParams memory params = IRouter
            .ExactInputSingleParams({
                tokenIn: tokenAddress,
                tokenOut: address(router.WETH9()),
                fee: 500,
                recipient: address(this),
                amountIn: tokenAmount,
                amountOutMinimum: expectedAmount.mulDiv(0.95 ether, 1 ether), // 5% slippage
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(params);

        // Unwrap WETH to ETH
        IWETH9 weth = IWETH9(address(router.WETH9()));
        uint256 balance = weth.balanceOf(address(this));
        weth.withdraw(balance);
        // Securely transfer ETH to OpenZeppelin Defender Wallet
        (bool success, ) = OZW.call{value: balance}("");
        if (!success) {
            revert Errors.TransferFailed(OZW, expectedAmount);
        }
    }

    /// @dev Calculates the quote price at a given Uniswap tick value.
    /// @param tick The tick value used for the calculation.
    /// @param baseAmount The amount of the base token.
    /// @param baseToken The address of the base token.
    /// @param quoteToken The address of the quote token.
    /// @return quoteAmount The calculated quote amount.
    function _getQuoteAtTick(
        int24 tick,
        uint256 baseAmount,
        address baseToken,
        address quoteToken
    ) public pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
