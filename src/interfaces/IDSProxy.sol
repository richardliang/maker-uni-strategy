// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDSProxy {
  function execute(address _target, bytes memory _data) external payable returns (bytes32);
}