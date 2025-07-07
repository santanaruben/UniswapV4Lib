// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IHodlVault.sol";
import "./DataTypes.sol";
import "./Errors.sol";
import "./IEndpoint.sol";
import "./IFQuerier.sol";
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

library Utils {
    using MathUpgradeable for uint256;

    // address public constant OZW =

    // address public constant FQUERIER = address(0x57237f44e893468efDD568cA7dE1EA8A57d14c1b); // Vertex FQUERIER Base Mainnet
    address public constant FQUERIER = address(0x1693273B443699bee277eCbc60e2C8027E91995d); // Arbitrum Mainnet
    // address public constant FQUERIER = address(0x2F579046eC1e88Ff580ca5ED9373e91ece8894b0); // Arbitrum Testnet
    // address public constant FQUERIER = address(0x97F9430c279637267D43bcD996F789e1d52Efd60); // Mantle Sepolia
    // address public constant OZW = address(0xdd7257d94d0F269A598FB650d331406de5A46b11); // OpenZeppelin Defender Wallet Base Mainnet
    // address public constant OZW = address(0xB8df119948e3bb1cf2255EBAfc4b9CE35b11CA22); // OpenZeppelin Defender Wallet Arbitrum Mainnet
    address public constant OZW =
        address(0xc6B04026Ad05981840aD6bD77c924c67bAeCf0DC); // OpenZeppelin Defender Wallet Unit-test Arbitrum Mainnet
    // address public constant OZW = address(0x60153ec0A8151f11f8c0b32D069782bf0D366a3A); // OpenZeppelin Defender Wallet Arbitrum Testnet USDc
    // address public constant OZW = address(0xf196194986C39624143cD29B4864ef3C85c35542); // OpenZeppelin Defender Wallet Arbitrum Testnet BTC
    // address public constant OZW = address(0x0931D0553329b88792a7FA0F19676B5961106ACc); // OpenZeppelin Defender Wallet Mantle Sepolia
    bytes12 private constant DEFAULT_SUBACCOUNT_NAME =
        bytes12(abi.encodePacked("default"));
    string constant DEFAULT_REFERRAL_CODE = "-1";

    /**
     * @dev Calculates the required USDC reserve for the Transfer Bot in the current epoch.
     * @param hodl Address of the HodlVault contract.
     * @param asset Address of the asset (USDC) contract.
     * @return The amount of USDC needed to meet the target balance.
     */
    function CalculateTransferBotGasReserveDA(
        address hodl,
        address asset
    ) public view returns (uint256) {
        IHodlVault hodlVault = IHodlVault(hodl);
        uint256 calDecimals = 10 ** hodlVault.decimals();
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(asset);
        uint256 currentEpoch = hodlVault.CURRENT_EPOCH();
        if (currentEpoch == 0) return 0;
        uint256 targetBalance = hodlVault
            .TRANSFER_BOT_TARGET_WALLET_BALANCE_USDC();
        uint256 currentBalance = _asset.balanceOf(OZW);

        // Calculate the missing USDC amount to reach the target balance
        uint256 missingAmount = targetBalance > currentBalance
            ? targetBalance - currentBalance
            : 0;

        // Calculate the total fees to be collected for the current epoch
        uint256 totalFees = getPnLPerVaultToken(hodl, asset)
            ? (mgtFeePctVaultToken(hodl) + perfFeePctVaultToken(hodl, asset))
                .mulDiv(
                    hodlVault.VAULT_TOKEN_SUPPLY(currentEpoch - 1),
                    calDecimals
                )
            : mgtFeePctVaultToken(hodl).mulDiv(
                hodlVault.VAULT_TOKEN_SUPPLY(currentEpoch - 1),
                calDecimals
            );

        // Return the smaller amount between the missing USDC and the total fees
        return missingAmount < totalFees ? missingAmount : totalFees;
    }

    /**
     * @dev Determines if the profit per vault token for the current epoch is positive.
     * Returns false if the current epoch is 0 or if there are no vault tokens in the previous epoch.
     */
    function getPnLPerVaultToken(
        address hodl,
        address asset
    ) public view returns (bool) {
        IHodlVault hodlVault = IHodlVault(hodl);
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(asset);
        uint256 assetDecimals = 10 ** _asset.decimals();
        uint256 currentEpoch = hodlVault.CURRENT_EPOCH();
        if (
            (currentEpoch == 0) ||
            (hodlVault.VAULT_TOKEN_SUPPLY(currentEpoch - 1) == 0)
        ) {
            return false;
        }
        return (hodlVault.DEX_WALLET_BALANCE().mulDiv(
            assetDecimals,
            hodlVault.VAULT_TOKEN_SUPPLY(currentEpoch - 1).mulDiv(
                assetDecimals,
                10 ** hodlVault.decimals()
            )
        ) >= hodlVault.VAULT_TOKEN_PRICE(currentEpoch - 1));
    }

    /**
     * @dev Calculates the management fee per vault token for the current epoch.
     * Returns 0 if the current epoch is 0.
     */
    function mgtFeePctVaultToken(address hodl) public view returns (uint256) {
        IHodlVault hodlVault = IHodlVault(hodl);
        uint256 currentEpoch = hodlVault.CURRENT_EPOCH();
        if (currentEpoch == 0) {
            return 0;
        } else {
            uint256 lastEpoch = currentEpoch - 1;
            return
                hodlVault.VAULT_TOKEN_PRICE(lastEpoch).mulDiv(
                    hodlVault.MANAGEMENT_FEE_PERCENTAGE().mulDiv(
                        hodlVault.EPOCH_DURATION(),
                        31556926
                    ), // 31556926 represents the number of seconds in a year (365.24 days)
                    10 ** hodlVault.decimals(),
                    MathUpgradeable.Rounding.Down
                );
        }
    }

    /**
     * @dev Calculates the performance fee per vault token for the current epoch.
     * Returns 0 if the current epoch is 0 or if there is no profit.
     */
    function perfFeePctVaultToken(
        address hodl,
        address asset
    ) public view returns (uint256) {
        IHodlVault hodlVault = IHodlVault(hodl);
        if (hodlVault.CURRENT_EPOCH() == 0) return 0;
        if (getPnLPerVaultToken(hodl, asset)) {
            return
                pnLPerVaultToken(hodl, asset).mulDiv(
                    hodlVault.PERFORMANCE_FEE_PERCENTAGE(),
                    10 ** hodlVault.decimals(),
                    MathUpgradeable.Rounding.Down
                );
        } else {
            return 0;
        }
    }

    /**
     * @dev Calculates the Profit/Loss per vault token for the current epoch.
     * Returns the difference between the DEX wallet balance per vault token and the previous vault token price.
     */
    function pnLPerVaultToken(
        address hodl,
        address asset
    ) public view returns (uint256) {
        IHodlVault hodlVault = IHodlVault(hodl);
        uint256 hodlDecimals = 10 ** hodlVault.decimals();
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(asset);
        uint256 assetDecimals = 10 ** _asset.decimals();
        uint256 currentEpoch = hodlVault.CURRENT_EPOCH();
        if (
            (currentEpoch == 0) ||
            (hodlVault.VAULT_TOKEN_SUPPLY(currentEpoch - 1) == 0)
        ) {
            return 0;
        }

        // Calcula el precio por token con el DEX_WALLET_BALANCE
        uint256 pricePerTokenFromDex = hodlVault.DEX_WALLET_BALANCE().mulDiv(
            assetDecimals,
            hodlVault.VAULT_TOKEN_SUPPLY(currentEpoch - 1).mulDiv(
                assetDecimals,
                hodlDecimals,
                MathUpgradeable.Rounding.Down // Asegurar redondeo hacia abajo
            ),
            MathUpgradeable.Rounding.Down // Asegurar redondeo hacia abajo
        );

        uint256 previousTokenPrice = hodlVault.VAULT_TOKEN_PRICE(
            currentEpoch - 1
        );

        // Asegurar que el precio anterior no sea cero
        if (previousTokenPrice == 0) {
            previousTokenPrice = 1e6; // Valor por defecto: 1 USDC con 6 decimales
        }

        if (getPnLPerVaultToken(hodl, asset)) {
            // Ganancia - precio actual mayor que el anterior
            return pricePerTokenFromDex - previousTokenPrice;
        } else {
            // Pérdida - precio anterior mayor que el actual
            return previousTokenPrice - pricePerTokenFromDex;
        }
    }

    /**
     * @dev Updates the vault token price for the current epoch.
     * @param hodl Address of the HodlVault contract.
     * @param asset Address of the asset (USDC) contract.
     * @return The updated vault token price.
     */
    function UpdateVaultPriceToken(
        address hodl,
        address asset
    ) public view returns (uint256) {
        uint256 mgtFee = mgtFeePctVaultToken(hodl);
        uint256 perfFee = perfFeePctVaultToken(hodl, asset);
        uint256 pnLVT = pnLPerVaultToken(hodl, asset);
        uint256 tokenPrice = LastVaultPriceToken(hodl, asset);
        if (getPnLPerVaultToken(hodl, asset)) {
            return (tokenPrice + pnLVT) - (mgtFee + perfFee) + 1;
        } else {
            return tokenPrice - (pnLVT + (mgtFee + perfFee)) + 1;
        }
    }

    function LastVaultPriceToken(
        address hodl,
        address asset
    ) public view returns (uint256) {
        IHodlVault hodlVault = IHodlVault(hodl);
        uint256 currentEpoch = hodlVault.CURRENT_EPOCH();
        uint256 lastPrice;
        // Partial fix if Finalize epoch failed at some point
        if (currentEpoch >= 1) {
            uint256 lastEpoch = currentEpoch - 1;
            // If the price for the last epoch is <= 10, we search backwards for a price >= 10.
            if (hodlVault.VAULT_TOKEN_PRICE(lastEpoch) <= 10) {
                bool found = false;

                // Iterate backwards over previous epochs, including epoch 0.
                // We start from `lastEpoch + 1` and decrement down to 1 so that we can safely
                // reach index 0 without causing an underflow in uint256.
                for (uint256 i = lastEpoch + 1; i > 0; i--) {
                    uint256 idx = i - 1; // Actual epoch index
                    if (hodlVault.VAULT_TOKEN_PRICE(idx) >= 10) {
                        // Found a non-zero price (or >= 10 in this case).
                        lastPrice = hodlVault.VAULT_TOKEN_PRICE(idx);
                        found = true;
                        break;
                    }

                    // If idx == 0, the loop will exit naturally when i-- triggers i to become 0.
                }

                // If no price >= 10 was found in any of the previous epochs:
                if (!found) {
                    // Initialize the first epoch price
                    uint256 initialPrice = (1 ether *
                        10 ** IERC20MetadataUpgradeable(asset).decimals()) /
                        hodlVault.DECIMAL_FACTOR();
                    lastPrice = initialPrice;
                }
            } else {
                lastPrice = hodlVault.VAULT_TOKEN_PRICE(lastEpoch);
            }
        } else {
            lastPrice =
                (1 ether * 10 ** IERC20MetadataUpgradeable(asset).decimals()) /
                hodlVault.DECIMAL_FACTOR();
        }
        return lastPrice;
    }

    /*//////////////////////////////////////////////////////////////
                    COMMAND SHORTCUTS FOR VERTEX
    //////////////////////////////////////////////////////////////*/

    struct LinkSigner {
        bytes32 sender; // Subaccount of the contract
        bytes32 signer; // Subaccount of the external account
        uint64 nonce; // Unique transaction identifier
    }

    struct WithdrawCollateral {
        bytes32 sender; // Subaccount initiating the withdrawal
        uint32 productId; // ID of the product to withdraw from
        uint128 amount; // Amount of collateral to withdraw
        uint64 nonce; // Unique transaction identifier
    }

    /**
     * @dev Retrieves the Vertex balance by calling the getUnhealthBalance function.
     * @return balance The current balance from the Vertex subaccount.
     */
    function getVertexBalance() public returns (uint256 balance) {
        (, balance) = getUnhealthBalance();
    }

    // Retrieves the subaccount information and calculates the balance based on health status
    function getUnhealthBalance()
        public
        returns (IFQuerier.SubaccountInfo memory unhBalance, uint256 balance)
    {
        // Fetch subaccount information from the FQuerier contract
        unhBalance = IFQuerier(FQUERIER).getSubaccountInfo(
            bytes32(
                abi.encodePacked(
                    uint160(address(this)),
                    DEFAULT_SUBACCOUNT_NAME
                )
            )
        );
        // Calculate balance based on health status
        balance = unhBalance.healths[2].health < 0
            ? 0
            : uint256(uint128(unhBalance.healths[2].health));
    }

    /**
     * @dev Links an external account's subaccount to the contract's subaccount on the Vertex platform.
     * @param vertexEndpoint Address of the Vertex endpoint contract.
     * @param asset Address of the asset (USDC) contract.
     * @param externalAccount Address of the external account to link.
     */
    function linkVertexSigner(
        address vertexEndpoint,
        address asset,
        address externalAccount
    ) public {
        _payFeeVertex(vertexEndpoint, asset, 0);
        bytes32 contractSubaccount = bytes32(
            abi.encodePacked(uint160(address(this)), DEFAULT_SUBACCOUNT_NAME)
        );
        bytes32 externalSubaccount = bytes32(
            abi.encodePacked(uint160(externalAccount), DEFAULT_SUBACCOUNT_NAME)
        );
        LinkSigner memory linkSigner = LinkSigner(
            contractSubaccount,
            externalSubaccount,
            IEndpoint(vertexEndpoint).getNonce(externalAccount)
        );
        bytes memory txs = abi.encodePacked(uint8(19), abi.encode(linkSigner));
        IEndpoint(vertexEndpoint).submitSlowModeTransaction(txs);
    }

    /**
     * @dev Deposits collateral into the Vertex platform with a referral code.
     * @param vertexEndpoint Address of the Vertex endpoint contract.
     * @param asset Address of the asset (USDC) contract.
     * @param productId ID of the product to deposit into.
     * @param amount Amount of collateral to deposit.
     */
    function depositCollateralWithReferral(
        address vertexEndpoint,
        address asset,
        uint32 productId,
        uint256 amount
    ) public {
        _payFeeVertex(vertexEndpoint, asset, amount);
        bytes32 addrBytes32 = bytes32(
            abi.encodePacked(uint160(address(this)), DEFAULT_SUBACCOUNT_NAME)
        );
        IEndpoint(vertexEndpoint).depositCollateralWithReferral(
            addrBytes32,
            productId,
            uint128(amount),
            DEFAULT_REFERRAL_CODE
        );
    }

    /**
     * @dev Withdraws collateral from the Vertex platform.
     * @param vertexEndpoint Address of the Vertex endpoint contract.
     * @param asset Address of the asset (USDC) contract.
     * @param productId ID of the product to withdraw from.
     * @param amount Amount of collateral to withdraw.
     */
    function withdrawVertexCollateral(
        address vertexEndpoint,
        address asset,
        uint32 productId,
        uint256 amount
    ) public {
        _payFeeVertex(vertexEndpoint, asset, 0);
        uint64 nonce = IEndpoint(vertexEndpoint).getNonce(address(this));
        WithdrawCollateral memory withdrawal = WithdrawCollateral(
            bytes32(
                abi.encodePacked(
                    uint160(address(this)),
                    DEFAULT_SUBACCOUNT_NAME
                )
            ),
            productId,
            uint128(amount),
            nonce
        );
        bytes memory txs = abi.encodePacked(uint8(2), abi.encode(withdrawal));
        IEndpoint(vertexEndpoint).submitSlowModeTransaction(txs);
    }

    /**
     * @dev Handles the fee payment for Vertex transactions.
     * @param vertexEndpoint Address of the Vertex endpoint contract.
     * @param asset Address of the asset (USDC) contract.
     * @param amount Amount of collateral to deposit.
     */
    function _payFeeVertex(
        address vertexEndpoint,
        address asset,
        uint256 amount
    ) internal {
        IERC20MetadataUpgradeable _asset = IERC20MetadataUpgradeable(asset);
        // Increase allowance from Vault to Vertex
        SafeERC20Upgradeable.safeIncreaseAllowance(
            _asset,
            vertexEndpoint,
            amount + 10 ** _asset.decimals()
        );
        // Transfer fee from TraderBotWallet to Vault
        SafeERC20Upgradeable.safeTransferFrom(
            _asset,
            address(OZW),
            address(this),
            10 ** _asset.decimals()
        );
    }
}
