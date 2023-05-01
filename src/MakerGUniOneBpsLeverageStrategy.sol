// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/MakerInterfaces.sol";
import { IEulerFlashLoanCaller } from "./interfaces/IEulerFlashLoanCaller.sol";
import { ProxyPermission } from "./ProxyPermission.sol";
import { GUniStrategyHelper } from "./interfaces/GUniStrategyHelper.sol";

/// @title Zap contract that uses flashloans to lever the GUNI V3 DAIUSDC pool on Maker
/// @dev Uses the Maker PSM for feeless 1:1 DAI USDC swaps and Euler for feeless flashloans
/// IMPORTANT ASSUMPTIONS
/// - This contract is NOT MEV SAFE. Use Flashbots or a private RPC to avoid frontrunners
/// - Addresses are hardcoded as constants. If any change, must redeploy
/// - Assume there are no fees for the PSM. If fees are turned on, the script will fail
contract MakerGUniOneBpsLeverageStrategy is GUniStrategyHelper, ProxyPermission {

    /// @notice Levers a Gelato V3 DAI USDC position owned using a Euler flash loan. Must be called by DSProxy.
    /// @dev Calls an external contract to receive the flash loan due to callback flow. DSProxy authorizes that contract temporarily
    function lever(
        uint256 _daiLoanAmount,
        uint256 _daiToDeposit,
        uint256 _cdp,
        address _makerUniStrategy,
        address _eulerFlashLoanCaller
    ) public {
        bytes memory flashLoanData = abi.encode(
            FlashLoanParams({
                daiLoanAmount: _daiLoanAmount,
                daiToDepositOrLiquidityToWithdraw: _daiToDeposit,
                cdp: _cdp,
                dsProxy: address(this),
                makerUniStrategy: _makerUniStrategy,
                eulerFlashLoanCaller: _eulerFlashLoanCaller,
                payer: msg.sender,
                isLever: true
            })
        );

        /// Authorize caller contract to DSProxy
        givePermission(_eulerFlashLoanCaller);

        IEulerFlashLoanCaller(_eulerFlashLoanCaller).flashloan(flashLoanData);

        /// Remove authorization for caller contract from DSProxy
        removePermission(_eulerFlashLoanCaller);
    }

    /// @notice Delevers a Gelato V3 DAI USDC position owned using a Euler flash loan. Must be called by DSProxy.
    /// @dev Calls an external contract to receive the flash loan due to callback flow. DSProxy authorizes that contract temporarily
    function delever(
        uint256 _daiLoanAmount,
        uint256 _liquidityToWithdraw,
        uint _cdp,
        address _makerUniStrategy,
        address _eulerFlashLoanCaller
    ) public {
        bytes memory flashLoanData = abi.encode(
            FlashLoanParams({
                daiLoanAmount: _daiLoanAmount,
                daiToDepositOrLiquidityToWithdraw: _liquidityToWithdraw,
                cdp: _cdp,
                dsProxy: address(this),
                makerUniStrategy: _makerUniStrategy,
                eulerFlashLoanCaller: _eulerFlashLoanCaller,
                payer: msg.sender,
                isLever: false
            })
        );

        /// Authorize caller contract to DSProxy
        givePermission(_eulerFlashLoanCaller);

        IEulerFlashLoanCaller(_eulerFlashLoanCaller).flashloan(flashLoanData);

        /// Remove authorization for caller contract from DSProxy
        removePermission(_eulerFlashLoanCaller);
    }

    /// @notice Callback function from EulerFlashLoanCaller contract for lever
    function leverCallback(FlashLoanParams memory _flashLoanParams) public {
        // Get pooled amounts on GUNI. Token0 is DAI Token1 is USDC
        (uint256 daiRequired, uint256 usdcRequired, ) = G_UNI_DAIUSDC_POOL_ONE_BPS.getMintAmounts(
            _flashLoanParams.daiToDepositOrLiquidityToWithdraw,
            _flashLoanParams.daiToDepositOrLiquidityToWithdraw
        );

        /// Approve DAI to PSM
        DAI.approve(address(DSS_PSM), type(uint256).max);
        /// Approve tokens to Gelato V3
        DAI.approve(address(G_UNI_ROUTER), type(uint256).max);
        USDC.approve(address(G_UNI_ROUTER), type(uint256).max);

        /// Swap PSM from DAI to USDC. Assume 1:1 USDC with no toll fees
        DSS_PSM.buyGem(address(this), usdcRequired);


        /// Add liquidity
        ( , , uint256 balanceOfLiquidityShares) = G_UNI_ROUTER.addLiquidity(
            G_UNI_DAIUSDC_POOL_ONE_BPS,
            daiRequired,
            usdcRequired,
            daiRequired,
            usdcRequired,
            address(this)
        );

        /// Approve max liquidity to adapter
        G_UNI_DAIUSDC_POOL_ONE_BPS.approve(address(G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN), type(uint256).max);

        address urn = MANAGER.urns(_flashLoanParams.cdp);
        bytes32 ilk = MANAGER.ilks(_flashLoanParams.cdp);

        /// Updates stability fee rate
        uint rate = JUG.drip(ilk);
        /// Gets DAI balance of the urn in the vat
        uint daiVatBalance = VAT.dai(urn);

        /// Deposit in Adapter
        G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN.join(urn, balanceOfLiquidityShares);

        /// Lock collateral and borrow loan amount of DAI from Maker
        MANAGER.frob(_flashLoanParams.cdp, int256(balanceOfLiquidityShares), _normalizeDrawAmount(_flashLoanParams.daiLoanAmount, rate, daiVatBalance));
        
        /// Moves the DAI amount (balance in the vat in rad) to proxy's address
        MANAGER.move(_flashLoanParams.cdp, address(this), toRad(_flashLoanParams.daiLoanAmount));

        /// Allows adapter to access to proxy's DAI balance in the vat
        if (VAT.can(address(this), address(DAI_JOIN)) == 0) {
            VAT.hope(address(DAI_JOIN));
        }

        /// Exits DAI to DSPROXY as a token
        DAI_JOIN.exit(address(this), _flashLoanParams.daiLoanAmount);

        /// Transfer back to flashloan caller contract
        DAI.transfer(_flashLoanParams.eulerFlashLoanCaller, _flashLoanParams.daiLoanAmount);
    }

    /// @notice Callback function from EulerFlashLoanCaller contract for delvering a position
    function deleverCallback(FlashLoanParams memory _flashLoanParams) public {
        /// Repay DAI loan in Maker Vault
        address urn = MANAGER.urns(_flashLoanParams.cdp);
        bytes32 ilk = MANAGER.ilks(_flashLoanParams.cdp);

        /// if _amount is higher than current debt, repay all debt
        uint256 debt = _getAllDebt(address(VAT), urn, urn, ilk);
        uint256 repayAmount = _flashLoanParams.daiLoanAmount > debt ? debt : _flashLoanParams.daiLoanAmount;

        /// Approve and deposit DAI in adapter and repay
        DAI.approve(address(DAI_JOIN), repayAmount);
        DAI_JOIN.join(urn, repayAmount);
        
        /// convert to 18 decimals for maker frob if needed
        uint256 frobAmount = convertTo18(address(G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN), _flashLoanParams.daiToDepositOrLiquidityToWithdraw);
        /// Payback and remove collateral
        MANAGER.frob(
            _flashLoanParams.cdp,
            -toPositiveInt(frobAmount),
            _normalizePaybackAmount(address(VAT), VAT.dai(urn), urn, ilk)
        );

        /// withdraw from vault and move to proxy balance
        MANAGER.flux(_flashLoanParams.cdp, address(this), frobAmount);

        /// withdraw the tokens from Join
        G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN.exit(address(this), _flashLoanParams.daiToDepositOrLiquidityToWithdraw);

        /// Remove liquidity
        G_UNI_DAIUSDC_POOL_ONE_BPS.approve(address(G_UNI_ROUTER), type(uint256).max);
        ( , uint256 amountUsdc, ) = G_UNI_ROUTER.removeLiquidity(
            G_UNI_DAIUSDC_POOL_ONE_BPS,
            _flashLoanParams.daiToDepositOrLiquidityToWithdraw,
            0, /// NOTE: USE FLASHBOTS TO AVOID MEV
            0, /// NOTE: USE FLASHBOTS TO AVOID MEV
            address(this)
        );

        /// Approve USDC to PSM JOIN (not PSM directly)
        USDC.approve(address(USDC_PSM_JOIN), type(uint256).max);

        /// Swap USDC to DAI using PSM. Assume 1:1 with no toll fees
        DSS_PSM.sellGem(address(this), amountUsdc);

        /// Transfer
        DAI.transfer(_flashLoanParams.eulerFlashLoanCaller, _flashLoanParams.daiLoanAmount);

        /// Transfer remaining DAI to user
        uint256 remainingDai = DAI.balanceOf(address(this));
        DAI.transfer(_flashLoanParams.payer, remainingDai);
    }

    /// @notice Returns a normalized debt _amount based on the current rate. Adapted from DeFi Saver https://github.com/defisaver/defisaver-v3-contracts/blob/main/contracts/actions/mcd/helpers/McdHelper.sol#L26
    function _normalizeDrawAmount(uint _amount, uint _rate, uint _daiVatBalance) internal pure returns (int dart) {
        if (_daiVatBalance < _amount * RAY) {
            dart = toPositiveInt((_amount * RAY - _daiVatBalance) / _rate);
            dart = uint(dart) * _rate < _amount * RAY ? dart + 1 : dart;
        }
    }

    /// @notice Gets Dai amount in Vat which can be added to Cdp. Adapted from DeFi Saver https://github.com/defisaver/defisaver-v3-contracts/blob/main/contracts/actions/mcd/helpers/McdHelper.sol#L61
    function _normalizePaybackAmount(address _vat, uint256 _daiBalance, address _urn, bytes32 _ilk) internal view returns (int amount) {

        (, uint rate,,,) = VatLike(_vat).ilks(_ilk);
        (, uint art) = VatLike(_vat).urns(_ilk, _urn);

        amount = toPositiveInt(_daiBalance / rate);
        amount = uint(amount) <= art ? - amount : - toPositiveInt(art);
    }

    /// @notice Gets the whole debt of the CDP. Adapted from DeFi Saver https://github.com/defisaver/defisaver-v3-contracts/blob/main/contracts/actions/mcd/helpers/McdHelper.sol#L75
    function _getAllDebt(address _vat, address _usr, address _urn, bytes32 _ilk) internal view returns (uint daiAmount) {
        (, uint rate,,,) = VatLike(_vat).ilks(_ilk);
        (, uint art) = VatLike(_vat).urns(_ilk, _urn);
        uint dai = VatLike(_vat).dai(_usr);

        uint rad = art * rate - dai;
        daiAmount = rad / RAY;

        // handles precision error (off by 1 wei)
        daiAmount = daiAmount * RAY < rad ? daiAmount + 1 : daiAmount;
    }

    /// @notice Converts a number to Rad precision. Adapted from DeFi Saver https://github.com/defisaver/defisaver-v3-contracts/blob/main/contracts/actions/mcd/helpers/McdHelper.sol#L35
    function toRad(uint _wad) internal pure returns (uint) {
        return _wad * (10 ** 27);
    }

    /// @notice Converts a number to 18 decimal precision. Adapted from DeFi Saver https://github.com/defisaver/defisaver-v3-contracts/blob/main/contracts/actions/mcd/helpers/McdHelper.sol#L43
    function convertTo18(address _joinAddr, uint256 _amount) internal view returns (uint256) {
        return _amount * (10 ** (18 - GemJoinLike(_joinAddr).dec()));
    }

    /// @notice Converts a uint to int and checks if positive. Adapted from DeFi Saver https://github.com/defisaver/defisaver-v3-contracts/blob/main/contracts/actions/mcd/helpers/McdHelper.sol#L49
    function toPositiveInt(uint _x) internal pure returns (int y) {
        y = int(_x);
        if (y < 0){
            revert IntOverflow();
        }
    }
}