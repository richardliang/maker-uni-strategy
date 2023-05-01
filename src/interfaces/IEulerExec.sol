// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IEulerExec {
  function deferLiquidityCheck(address account, bytes memory data) external;
}