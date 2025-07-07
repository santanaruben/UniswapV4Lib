// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../src/calculum-lib/IHodlVault.sol";

contract MockHodlVault is IHodlVault {
    uint256 public currentEpoch;
    mapping(uint256 => uint256) public vaultTokenSupply_;
    mapping(uint256 => uint256) public vaultTokenPrice_;
    uint256 public dexWalletBalance_;
    uint256 public performanceFeePercentage_;
    uint256 public managementFeePercentage_;
    uint256 public epochDuration_;
    uint256 public decimalFactor_;
    uint256 public transferBotTargetWalletBalanceUsdc_;

    // Funciones faltantes y variables para mockear IHodlVault
    uint256 public epochStart_;
    uint256 public maxDeposit_;
    uint256 public minDeposit_;
    uint256 public maxTotalDeposit_;
    uint256 public transferBotMinWalletBalanceUsdc_;
    uint256 public transferBotMinWalletBalanceEth_;
    uint256 public maintenancePeriodPreStart_;
    uint256 public maintenancePeriodPostStart_;
    uint256 public openZeppelinDefenderWallet__;
    uint256 public traderBotWallet__;
    uint256 public treasuryWallet__;

    constructor(
        uint256 _currentEpoch,
        uint256 _dexWalletBalance,
        uint256 _performanceFeePercentage,
        uint256 _managementFeePercentage,
        uint256 _epochDuration,
        uint256 _decimalFactor,
        uint256 _transferBotTargetWalletBalanceUsdc
    ) {
        currentEpoch = _currentEpoch;
        dexWalletBalance_ = _dexWalletBalance;
        performanceFeePercentage_ = _performanceFeePercentage;
        managementFeePercentage_ = _managementFeePercentage;
        epochDuration_ = _epochDuration;
        decimalFactor_ = _decimalFactor;
        transferBotTargetWalletBalanceUsdc_ = _transferBotTargetWalletBalanceUsdc;

        // Inicialización de funciones faltantes con valores por defecto o cero
        epochStart_ = 0;
        maxDeposit_ = type(uint256).max; // O un valor más sensato para el test
        minDeposit_ = 0;
        maxTotalDeposit_ = type(uint256).max;
        transferBotMinWalletBalanceUsdc_ = 0;
        transferBotMinWalletBalanceEth_ = 0;
        maintenancePeriodPreStart_ = 0;
        maintenancePeriodPostStart_ = 0;
        openZeppelinDefenderWallet__ = 0;
        traderBotWallet__ = 0;
        treasuryWallet__ = 0;
    }

    function EPOCH_START() external view override returns (uint256) {
        return epochStart_;
    }

    function MANAGEMENT_FEE_PERCENTAGE() external view override returns (uint256) {
        return managementFeePercentage_;
    }

    function PERFORMANCE_FEE_PERCENTAGE() external view override returns (uint256) {
        return performanceFeePercentage_;
    }

    function DECIMAL_FACTOR() external view override returns (uint256) {
        return decimalFactor_;
    }

    function VAULT_TOKEN_PRICE(uint256 epoch) external view override returns (uint256) {
        return vaultTokenPrice_[epoch];
    }

    function VAULT_TOKEN_SUPPLY(uint256 epoch) external view override returns (uint256) {
        return vaultTokenSupply_[epoch];
    }

    function DEX_WALLET_BALANCE() external view override returns (uint256) {
        return dexWalletBalance_;
    }

    function MAX_DEPOSIT() external view override returns (uint256) {
        return maxDeposit_;
    }

    function MIN_DEPOSIT() external view override returns (uint256) {
        return minDeposit_;
    }

    function MAX_TOTAL_DEPOSIT() external view override returns (uint256) {
        return maxTotalDeposit_;
    }

    function TRANSFER_BOT_MIN_WALLET_BALANCE_USDC() external view override returns (uint256) {
        return transferBotMinWalletBalanceUsdc_;
    }

    function TRANSFER_BOT_TARGET_WALLET_BALANCE_USDC() external view override returns (uint256) {
        return transferBotTargetWalletBalanceUsdc_;
    }

    function TRANSFER_BOT_MIN_WALLET_BALANCE_ETH() external view override returns (uint256) {
        return transferBotMinWalletBalanceEth_;
    }

    function EPOCH_DURATION() external view override returns (uint256) {
        return epochDuration_;
    }

    function CURRENT_EPOCH() external view override returns (uint256) {
        return currentEpoch;
    }

    function MAINTENANCE_PERIOD_PRE_START() external view override returns (uint256) {
        return maintenancePeriodPreStart_;
    }

    function MAINTENANCE_PERIOD_POST_START() external view override returns (uint256) {
        return maintenancePeriodPostStart_;
    }

    function openZeppelinDefenderWallet() external view override returns (uint256) {
        return openZeppelinDefenderWallet__;
    }

    function traderBotWallet() external view override returns (uint256) {
        return traderBotWallet__;
    }

    function treasuryWallet() external view override returns (uint256) {
        return treasuryWallet__;
    }

    // Implementación de getPnLPerVaultToken para el mock
    function getPnLPerVaultToken() external pure override returns (bool) {
        // Simplificado para el mock: siempre retorna true para que perfFeePctVaultToken se calcule
        return true;
    }

    function decimals() external pure override returns (uint8) {
        return 18; // Ajustar a 18 decimales para los tokens de bóveda
    }

    function setVaultTokenSupply(uint256 epoch, uint256 supply) public {
        vaultTokenSupply_[epoch] = supply;
    }

    function setVaultTokenPrice(uint256 epoch, uint256 price) public {
        vaultTokenPrice_[epoch] = price;
    }

    function setDexWalletBalance(uint256 _dexWalletBalance) public {
        dexWalletBalance_ = _dexWalletBalance;
    }

    function setCurrentEpoch(uint256 _currentEpoch) public {
        currentEpoch = _currentEpoch;
    }

    function setPerformanceFeePercentage(uint256 _performanceFeePercentage) public {
        performanceFeePercentage_ = _performanceFeePercentage;
    }

    function setManagementFeePercentage(uint256 _managementFeePercentage) public {
        managementFeePercentage_ = _managementFeePercentage;
    }

    function setEpochDuration(uint256 _epochDuration) public {
        epochDuration_ = _epochDuration;
    }

    function setDecimalFactor(uint256 _decimalFactor) public {
        decimalFactor_ = _decimalFactor;
    }
} 