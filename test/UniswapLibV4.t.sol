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
import {Utils} from "../src/calculum-lib/Utils.sol";
import {MockHodlVault} from "./mocks/MockHodlVault.sol";
import {MockERC20Metadata} from "./mocks/MockERC20Metadata.sol";
import {MathUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";

contract UniswapLibV4Test is Test, Deployers {

    using SafeERC20 for IERC20;
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using MathUpgradeable for uint256;

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

        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        Currency nativeETH = Currency.wrap(address(0));

        // New address to test OZW
        externalUser = vm.addr(1); 

        // externalUser approves (this contract) UniswapLibV4Test in order to do the safeTransferFrom
        vm.prank(externalUser);
        MockERC20(Currency.unwrap(currency1)).approve(address(this), type(uint256).max);
        vm.prank(externalUser);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);

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

        // Para este test, creamos una instancia de MockHodlVault
        MockHodlVault mockHodlVault = new MockHodlVault(
            1, // currentEpoch
            100000e6, // dexWalletBalance
            1e16, // performanceFeePercentage (1% escalado a 18 decimales)
            5e15, // managementFeePercentage (0.5% escalado a 18 decimales)
            31556926, // epochDuration
            1e18, // decimalFactor
            0 // transferBotTargetWalletBalanceUsdc
        );

        uint256 currentEpochForTest = 1;
        uint256 previousEpochForTest = currentEpochForTest - 1;
        uint256 vaultTokenSupplyPreviousEpochForTest = 100e18; // 100 tokens de bóveda (18 decimales)
        uint256 vaultTokenPricePreviousEpochForTest = 99e6; // Precio anterior: 99 USDC por token de bóveda (6 decimales)

        vm.prank(address(mockHodlVault));
        mockHodlVault.setVaultTokenSupply(previousEpochForTest, vaultTokenSupplyPreviousEpochForTest);
        vm.prank(address(mockHodlVault));
        mockHodlVault.setVaultTokenPrice(previousEpochForTest, vaultTokenPricePreviousEpochForTest);
        vm.prank(address(mockHodlVault));
        mockHodlVault.setDexWalletBalance(100000e18); // Usar el mismo dexWalletBalance que en la inicialización

        // Calcular los valores esperados para pnlPerVaultToken y expectedPerformanceFee
        // Replicar la lógica de Utils.sol para propósitos de assert y logging
        uint256 assetDecimalsForTest = 10 ** MockERC20Metadata(token).decimals();
        uint256 hodlDecimalsForTest = 10 ** mockHodlVault.decimals();

        uint256 pricePerTokenFromDexExpectedForTest = MathUpgradeable.mulDiv(
            mockHodlVault.DEX_WALLET_BALANCE(),
            assetDecimalsForTest,
            MathUpgradeable.mulDiv(
                vaultTokenSupplyPreviousEpochForTest,
                assetDecimalsForTest,
                hodlDecimalsForTest,
                MathUpgradeable.Rounding.Down
            ),
            MathUpgradeable.Rounding.Down
        );

        uint256 pnlPerVaultTokenExpectedForTest = pricePerTokenFromDexExpectedForTest - vaultTokenPricePreviousEpochForTest;

        uint256 expectedPerformanceFeeForTest = MathUpgradeable.mulDiv(
            pnlPerVaultTokenExpectedForTest,
            mockHodlVault.PERFORMANCE_FEE_PERCENTAGE(),
            hodlDecimalsForTest,
            MathUpgradeable.Rounding.Down
        );

        console2.log("pnlPerVaultTokenExpectedForTest: %i", pnlPerVaultTokenExpectedForTest);
        console2.log("expectedPerformanceFeeForTest: %i", expectedPerformanceFeeForTest);

        // swap token for ETH
        // BalanceDelta swapDeltaTx = 
        UniswapLibV4.swapTokensForETH(poolManager, swapRouter, token, externalUser, address(mockHodlVault));

        // check user balance
        // assertEq(swapDeltaTx.amount0(), int128(int256(externalUser.balance)));

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
    //     BalanceDelta swapDeltaTx = UniswapLibV4.swapTokensForETH(poolManager, swapRouter, token, externalUser);

    //     price1 = UniswapLibV4.getPriceInPaymentToken(poolManager, token);
    //     console2.log("price1: ", price1);
    //     price2 = UniswapLibV4.computePrice(poolManager, token, 1e18);
    //     console2.log("price2: ", price2);
    // }

    function testPerfFeePctVaultToken() public {
        // Datos de ejemplo para el mock de HodlVault y el token
        uint256 currentEpoch = 1; // Un epoch > 0
        uint256 dexWalletBalance = 10000e6; // 10,000 USDC (con 6 decimales)
        uint256 performanceFeePercentage = 1e16; // 1% (escalado a 18 decimales)
        uint256 managementFeePercentage = 5e15; // 0.5%
        uint256 epochDuration = 31556926; // Un año en segundos
        uint256 decimalFactor = 1e18; // Factor decimal de la bóveda
        uint256 transferBotTargetWalletBalanceUsdc = 0;

        // Desplegar el mock de HodlVault
        MockHodlVault mockHodlVault = new MockHodlVault(
            currentEpoch,
            dexWalletBalance,
            performanceFeePercentage,
            managementFeePercentage,
            epochDuration,
            decimalFactor,
            transferBotTargetWalletBalanceUsdc
        );

        // Desplegar el mock de ERC20Metadata (token de ejemplo USDC)
        MockERC20Metadata mockUSDC = new MockERC20Metadata("USDC", "USDC", 18);

        // Establecer el supply y el precio del token de la bóveda para el epoch anterior
        uint256 previousEpoch = currentEpoch - 1;
        uint256 vaultTokenSupplyPreviousEpoch = 100e18; // 100 tokens de bóveda
        uint256 vaultTokenPricePreviousEpoch = 99e6; // Precio anterior: 99 USDC por token de bóveda

        // Simular llamadas desde el contrato de prueba para establecer los valores
        vm.prank(address(mockHodlVault));
        mockHodlVault.setVaultTokenSupply(previousEpoch, vaultTokenSupplyPreviousEpoch);
        vm.prank(address(mockHodlVault));
        mockHodlVault.setVaultTokenPrice(previousEpoch, vaultTokenPricePreviousEpoch);
        vm.prank(address(mockHodlVault));
        mockHodlVault.setDexWalletBalance(dexWalletBalance);

        // Calcular el pnlPerVaultToken esperado manualmente para verificar la función
        // DEX_WALLET_BALANCE * assetDecimals / (VAULT_TOKEN_SUPPLY(prev) * assetDecimals / hodlDecimals)
        // hodlDecimals es 6 en el mock de HodlVault.decimals()
        // assetDecimals es 6 en el mock de USDC.decimals()

        // (10000e6 * 10^6) / (100e18 * 10^6 / 10^6) = 10000e12 / 100e18 = 100e-6 * 10^6 = 100
        // pricePerTokenFromDex = 10000e6 * 1e6 / (100e18 * 1e6 / 1e6) = 10000e12 / 100e18 = 100e-6
        // Esto es 100 en el contexto de 6 decimales para USDC
        // Lo calculamos como uint256(10000e6) porque el mock tiene 6 decimales.

        uint256 normalizedVaultTokenSupply = MathUpgradeable.mulDiv(vaultTokenSupplyPreviousEpoch, 10 ** mockUSDC.decimals(), 10 ** mockHodlVault.decimals(), MathUpgradeable.Rounding.Down);

        uint256 pricePerTokenFromDexExpected = MathUpgradeable.mulDiv(dexWalletBalance, 10 ** mockUSDC.decimals(), normalizedVaultTokenSupply, MathUpgradeable.Rounding.Down);

        // Redondear a la cantidad de decimales correcta para la comparación si es necesario
        // Asumiendo que todos los cálculos intermedios son enteros
        // pricePerTokenFromDexExpected = MathUpgradeable.mulDiv(dexWalletBalance, (10**6), MathUpgradeable.mulDiv(vaultTokenSupplyPreviousEpoch, (10**6), (10**6), MathUpgradeable.Rounding.Down), MathUpgradeable.Rounding.Down);

        // Este valor debe ser el que esperamos que getPnLPerVaultToken devuelva como ganancia
        uint256 pnlPerVaultTokenExpected = pricePerTokenFromDexExpected - vaultTokenPricePreviousEpoch;

        // Calcular la performanceFee esperada
        uint256 expectedPerformanceFee = MathUpgradeable.mulDiv(pnlPerVaultTokenExpected, performanceFeePercentage, 10 ** mockHodlVault.decimals(), MathUpgradeable.Rounding.Down);

        // Llamar a la función que queremos testear
        uint256 actualPerformanceFee = Utils.perfFeePctVaultToken(address(mockHodlVault), address(mockUSDC));

        console2.log("Calculated pnlPerVaultTokenExpected: %i", pnlPerVaultTokenExpected);
        console2.log("Calculated expectedPerformanceFee: %i", expectedPerformanceFee);
        console2.log("Actual performanceFee: %i", actualPerformanceFee);

        // Verificar que el resultado sea el esperado. Ajusta este valor si tus cálculos manuales difieren.
        assertEq(actualPerformanceFee, expectedPerformanceFee, "El performance fee calculado no coincide con el esperado");
    }
}
