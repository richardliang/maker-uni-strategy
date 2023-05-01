// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IEulerFlashLoanCaller {
    function flashloan(bytes memory data) external;
}