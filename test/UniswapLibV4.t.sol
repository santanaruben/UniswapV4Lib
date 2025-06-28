// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UniswapLibV4} from "../src/UniswapLibV4.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract UniswapLibV4Test is Test, Deployers {

    using SafeERC20 for IERC20;
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    receive() external payable {} // Permite que el contrato reciba ETH

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    // My hook;
    IHooks constant hook = IHooks(address(0x0)); // hook address
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address externalUser; // address to test OZW

    using UniswapLibV4 for *;

    function setUp() public {
        
        // New address to test OZW
        externalUser = vm.addr(1); 

        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        Currency nativeETH = Currency.wrap(address(0));

        // Create the pool with 1/1 price
        poolKey = PoolKey(nativeETH, currency1, 500, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        // liquidity amount (if not enough, it throws because of slippage)
        uint128 liquidityAmount = 10000e18;

        // get amounts expected for liquidity
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        console2.log("Liquidity Amount: %i in ETH format (%i in wei)", uint256(10000e18) / 10 ** 18, uint256(10000e18));
        console2.log("ETH Liquidity expected: %i ETH (%i in wei)",amount0Expected / 10 ** 18, amount0Expected);
        console2.log("Token Liquidity expected: %i Tokens (%i in wei)",amount1Expected / 10 ** 18, amount1Expected);

        // Mint 100e18 currency1 tokens to externalUser (100 tokens)
        MockERC20(Currency.unwrap(currency1)).mint(externalUser, 100e18);
        console2.log("User token balance at the start: %i Tokens (%i)", FullMath.mulDiv(MockERC20(Currency.unwrap(currency1)).balanceOf(externalUser), 1, 10 ** 18), MockERC20(Currency.unwrap(currency1)).balanceOf(externalUser));
        console2.log("User ETH balance at the start: %i ETH (%i)", FullMath.mulDiv(externalUser.balance, 1, 10 ** 18), externalUser.balance);

        // Mint the liquidity
        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testSwapTokensForETH() public {
        address token = Currency.unwrap(currency1);

        // externalUser approves (this contract) UniswapLibV4Test in order to do the safeTransferFrom
        vm.prank(externalUser);
        IERC20(token).approve(address(this), type(uint256).max); 

        // swap token for ETH
        BalanceDelta swapDeltaTx = UniswapLibV4._swapTokensForETH(poolManager, swapRouter, token, externalUser);

        // check user balance
        assertEq(swapDeltaTx.amount0(), int128(int256(externalUser.balance)));

        console2.log("User token balance at the end: %i Tokens (%i)", FullMath.mulDiv(MockERC20(Currency.unwrap(currency1)).balanceOf(externalUser), 1, 10 ** 18), MockERC20(Currency.unwrap(currency1)).balanceOf(externalUser));

        console2.log("User ETH balance at the end: %i ETH (%i)", FullMath.mulDiv(externalUser.balance, 1, 10 ** 18), externalUser.balance);
    }

    // function testSwapETHForTokens() public {

    //     address token = Currency.unwrap(currency1);

    //     (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

    //     // uint256 sqrtPriceX96 = UniswapLibV4.getPriceInPaymentToken2(poolManager, token);
    //     console2.log("Pool price (sqrtPriceX96) before the swap: ", sqrtPriceX96);

    //     int256 amountIn = 100e18;
    //     BalanceDelta swapDelta = swapRouter.swap{value: uint256(amountIn)}({
    //     // BalanceDelta swapDelta = swapRouter.swap({
    //         amountSpecified: -amountIn,
    //         amountLimit: 0, // Equivalent to amountOutMin: 0
    //         zeroForOne: true,
    //         poolKey: poolKey,
    //         hookData: Constants.ZERO_BYTES,
    //         receiver: address(externalUser),
    //         deadline: block.timestamp + 1
    //     });

    //     console2.log("swapDelta.amount0 (ETH): ", swapDelta.amount0());
    //     console2.log("swapDelta.amount1 (Token): ", swapDelta.amount1());

    //     console2.log("User token balance at the end: %i Tokens (%i)", FullMath.mulDiv(MockERC20(Currency.unwrap(currency1)).balanceOf(externalUser), 1, 10 ** 18), MockERC20(Currency.unwrap(currency1)).balanceOf(externalUser));

    //     (sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
    //     // sqrtPriceX96 = UniswapLibV4.getPriceInPaymentToken2(poolManager, token);
    //     console2.log("Pool price (sqrtPriceX96) after the swap: ", sqrtPriceX96);
    // }

    // function testGetPrice() public {
    //     address token = Currency.unwrap(currency1);
    //     uint256 price1 = UniswapLibV4.getPriceInPaymentToken(poolManager, token);
    //     console2.log("price1: ", price1);
    //     uint256 price2 = UniswapLibV4.computePrice(poolManager, token, 1e18);
    //     console2.log("price2: ", price2);

    //     vm.prank(externalUser);
    //     IERC20(token).approve(address(this), type(uint256).max); // externalUser approves UniswapLibV4Test
    //     BalanceDelta swapDeltaTx = UniswapLibV4._swapTokensForETH(poolManager, swapRouter, token, externalUser);

    //     price1 = UniswapLibV4.getPriceInPaymentToken(poolManager, token);
    //     console2.log("price1: ", price1);
    //     price2 = UniswapLibV4.computePrice(poolManager, token, 1e18);
    //     console2.log("price2: ", price2);
    // }
}
