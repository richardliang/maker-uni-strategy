// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDebtToken {
  function borrow(uint subAccountId, uint amount) external;
  function repay(uint subAccountId, uint amount) external;
}