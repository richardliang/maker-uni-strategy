// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDeferredLiquidityCheck {
    function onDeferredLiquidityCheck(bytes memory data) external;
}