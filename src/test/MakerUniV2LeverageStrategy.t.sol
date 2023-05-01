// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// ============ Imports ============

import "forge-std/Test.sol"; // Tests

import "../MakerUniV2LeverageStrategy.sol"; // MakerUniV2LeverageStrategy
import "../EulerFlashLoanCaller.sol"; // EulerFlashLoanCaller
import "../ProxyPermission.sol"; // EulerFlashLoanCaller
import { StrategyHelper } from "../interfaces/StrategyHelper.sol";


interface IERC20Balance {
  /// @notice Returns token balance
  function balanceOf(address) external returns (uint256);
}

interface IDSPROXY {
  function execute(address _target, bytes memory _data) external payable returns (bytes memory response);
}

/// @title MakerUniV2LeverageStrategyTest
/// @notice Tests MakerUniV2LeverageStrategyTest.sol
contract MakerUniV2LeverageStrategyTest is Test, StrategyHelper {
  // ============ Constants ============

  address constant VM_ADDR = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
  address constant NOT_OWNER = 0x016C8780e5ccB32E5CAA342a926794cE64d9C364;

  address constant USER = 0x21C30d17D9e61Ce139DFd2A3d167C5752246b938;
  uint256 constant CDP_ID = 28622;
  IDSPROXY constant DS_PROXY = IDSPROXY(0xB2b48FbD7f976003C1B3a0685E7c907b4F6372A3);

  // ============ Storage ============

  /// @dev Cheatcodes
  Vm public VM;
  EulerFlashLoanCaller public EULER_FLASHLOAN_CALLER;
  MakerUniV2LeverageStrategy public MAKER_UNI_STRATEGY;

  // ============ Setup tests ============

  function setUp() public {
    VM = Vm(VM_ADDR);
    EULER_FLASHLOAN_CALLER = new EulerFlashLoanCaller();
    MAKER_UNI_STRATEGY = new MakerUniV2LeverageStrategy();
  }

  // ============ Tests ============

  /// @notice Successful delever transaction
  function testDeleverSome() public {
    VM.startPrank(USER);
    UNIV2_DAIUSDC.approve(address(UNIV2_DAIUSDC_JOIN), type(uint256).max);

    uint256 collateralAmountToWithdraw = 1e16; // ~$22000
    uint256 daiToLoan = 2 * 1e22; // $20000
    bytes memory makerUniData = abi.encodeWithSelector(
      bytes4(keccak256(bytes("delever(uint256,uint256,uint256,address,address)"))),
      daiToLoan,
      collateralAmountToWithdraw,
      CDP_ID,
      address(MAKER_UNI_STRATEGY),
      address(EULER_FLASHLOAN_CALLER)
    );

    // Get pre data pre execution
    address urnHandler = MANAGER.urns(CDP_ID);
    (uint256 beforeInk, ) = VAT.urns(bytes32("UNIV2DAIUSDC-A"), urnHandler);
    uint256 preDaiBalance = DAI.balanceOf(USER);

    // Execute transaction
    DS_PROXY.execute(
      address(MAKER_UNI_STRATEGY),
      makerUniData
    );

    // Get pre data post execution
    (uint256 afterInk, ) = VAT.urns(bytes32("UNIV2DAIUSDC-A"), urnHandler);
    uint256 postDaiBalance = DAI.balanceOf(USER);

    // Verify LP collateral was decremented
    assertEq(
      beforeInk - collateralAmountToWithdraw,
      afterInk
    );

    // Verify user DAI balance increased
    assertApproxEqAbs(
      postDaiBalance - preDaiBalance,
      2 * 1e21, // $2000 DAI difference ($2200 collateral withdrawn - $2000 flashloan debt repaid)
      1e21 // +/-1000 DAI delta
    );

    // Verify Euler flashloan contract does not have permission to DSProxy
    address postCurrAuthority = address(DSAuth(address(DS_PROXY)).authority());
    DSGuard postGuard = DSGuard(postCurrAuthority);
    assertEq(
      postGuard.canCall(address(EULER_FLASHLOAN_CALLER), address(DS_PROXY), MAKER_UNI_STRATEGY.EXECUTE_SELECTOR()),
      false
    );

    VM.stopPrank();
  }

  /// @notice Successful lever transaction
  function testLever() public {
    // Delever some to free up debt ceiling
    testDeleverSome();

    VM.startPrank(USER);
    UNIV2_DAIUSDC.approve(address(UNIV2_DAIUSDC_JOIN), type(uint256).max);

    uint256 daiToDeposit = 11 * 1e21; // ~$11000
    uint256 daiToLoan = 23 * 1e21; // $23000
    bytes memory makerUniData = abi.encodeWithSelector(
      bytes4(keccak256(bytes("lever(uint256,uint256,uint256,address,address)"))),
      daiToLoan,
      daiToDeposit,
      CDP_ID,
      address(MAKER_UNI_STRATEGY),
      address(EULER_FLASHLOAN_CALLER)
    );

    // Get data pre execution
    address urnHandler = MANAGER.urns(CDP_ID);
    (uint256 beforeInk, uint256 beforeArt) = VAT.urns(bytes32("UNIV2DAIUSDC-A"), urnHandler);
    uint256 preDaiBalance = DAI.balanceOf(USER);

    // Verify Euler flashloan contract does not have permission to DSProxy
    address preCurrAuthority = address(DSAuth(address(DS_PROXY)).authority());
    DSGuard preGuard = DSGuard(preCurrAuthority);

    // Verify Euler flashloan contract does not have permission to DSProxy
    assertEq(
      preGuard.canCall(address(EULER_FLASHLOAN_CALLER), address(DS_PROXY), MAKER_UNI_STRATEGY.EXECUTE_SELECTOR()),
      false
    );

    // Execute flashloan
    DS_PROXY.execute(
      address(MAKER_UNI_STRATEGY),
      makerUniData
    );

    // Get pre data post execution
    (uint256 afterInk, uint256 afterArt) = VAT.urns(bytes32("UNIV2DAIUSDC-A"), urnHandler);
    (, uint256 rate, , , ) = VAT.ilks(bytes32("UNIV2DAIUSDC-A"));
    uint256 postDaiBalance = DAI.balanceOf(USER);

    // Verify normalized DAI debt was increased by flashloan amount accounting for rounding
    assertApproxEqAbs(
      (afterArt - beforeArt) * rate / 10 ** 27,
      daiToLoan,
      1
    );

    assertEq(
      preDaiBalance,
      postDaiBalance
    );

    // Verify LP collateral was incremented
    assertApproxEqAbs(
      afterInk - beforeInk,
      1e16, // 1 LP share ~= $2.2M
      1e15 // 0.1 LP share difference ~= $200k
    );

    // Verify Euler flashloan contract does not have permission to DSProxy
    address postCurrAuthority = address(DSAuth(address(DS_PROXY)).authority());
    DSGuard postGuard = DSGuard(postCurrAuthority);
    assertEq(
      postGuard.canCall(address(EULER_FLASHLOAN_CALLER), address(DS_PROXY), MAKER_UNI_STRATEGY.EXECUTE_SELECTOR()),
      false
    );

    VM.stopPrank();
  }
}
