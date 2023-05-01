// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IDeferredLiquidityCheck } from "./interfaces/IDeferredLiquidityCheck.sol";
import { IDSProxy } from "./interfaces/IDSProxy.sol";
import { StrategyHelper } from "./interfaces/StrategyHelper.sol";

/// @title Flashloan caller contract intended to be called by MakerUniV2LeverageStrategy contract
contract EulerFlashLoanCaller is IDeferredLiquidityCheck, StrategyHelper {

    /// @notice Callback function from EulerFlashLoanCaller contract for lever
    function flashloan(bytes memory _flashLoanData) external {
        /// Recipient of flashloan is this contract
        EULER_EXEC.deferLiquidityCheck(
            address(this),
            _flashLoanData
        );
    }

    /// @notice Callback function from Euler
    function onDeferredLiquidityCheck(bytes memory data) external override {
        require(msg.sender == EULER_MAIN, "Not allowed");

        FlashLoanParams memory flashLoanParams = abi.decode(data, (FlashLoanParams));

        /// Flashloan DAI from Euler
        DAI_DEBT_TOKEN.borrow(0, flashLoanParams.daiLoanAmount);

        /// Recipient is this contract so we forward to DSProxy
        DAI.transfer(flashLoanParams.dsProxy, flashLoanParams.daiLoanAmount);

        /// Execute lever or delever
        if (flashLoanParams.isLever) {
            IDSProxy(flashLoanParams.dsProxy).execute(
                flashLoanParams.makerUniStrategy,
                abi.encodeWithSignature(
                    "leverCallback((uint256,uint256,uint256,address,address,address,address,bool))",
                    flashLoanParams
                )
            );
        } else {
            IDSProxy(flashLoanParams.dsProxy).execute(
                flashLoanParams.makerUniStrategy,
                abi.encodeWithSignature(
                    "deleverCallback((uint256,uint256,uint256,address,address,address,address,bool))",
                    flashLoanParams
                )
            );
        }

        /// Approve DAI to Euler to repay loan
        DAI.approve(EULER_MAIN, type(uint256).max);

        /// Repay DAI flash loan from this contract
        DAI_DEBT_TOKEN.repay(0, flashLoanParams.daiLoanAmount);
    }
}