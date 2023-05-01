// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// ============ Imports ============

import "forge-std/Test.sol"; // Tests

import "../MakerGUniOneBpsLeverageStrategy.sol"; // MakerGUniOneBpsLeverageStrategy
import "../EulerFlashLoanCaller.sol"; // EulerFlashLoanCaller
import "../ProxyPermission.sol"; // EulerFlashLoanCaller
import { GUniStrategyHelper } from "../interfaces/GUniStrategyHelper.sol";


interface IERC20Balance {
  /// @notice Returns token balance
  function balanceOf(address) external returns (uint256);
}

interface IDSPROXY {
  function execute(address _target, bytes memory _data) external payable returns (bytes memory response);
}

/// @title MakerGUniOneBpsLeverageStrategyTest
/// @notice Tests MakerGUniOneBpsLeverageStrategyTest.sol
contract MakerGUniOneBpsLeverageStrategyTest is Test, GUniStrategyHelper {
  // ============ Constants ============

  address constant VM_ADDR = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
  address constant NOT_OWNER = 0x016C8780e5ccB32E5CAA342a926794cE64d9C364;

  address constant USER = 0x84a0308a55882c00A25590B8E7e39492a3f3754a;
  uint256 constant CDP_ID = 28875;
  IDSPROXY constant DS_PROXY = IDSPROXY(0x7137E51C6a0749B71cF4A057474e1548D58e6504);

  // ============ Storage ============

  /// @dev Cheatcodes
  Vm public VM;
  EulerFlashLoanCaller public EULER_FLASHLOAN_CALLER;
  MakerGUniOneBpsLeverageStrategy public MAKER_GUNI_STRATEGY;

  // ============ Setup tests ============

  function setUp() public {
    VM = Vm(VM_ADDR);
    EULER_FLASHLOAN_CALLER = new EulerFlashLoanCaller();
    MAKER_GUNI_STRATEGY = new MakerGUniOneBpsLeverageStrategy();
  }

  // ============ Tests ============

  /// @notice Successful delever transaction
  function testDeleverSome() public {
    VM.startPrank(USER);
    G_UNI_DAIUSDC_POOL_ONE_BPS.approve(address(G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN), type(uint256).max);

    uint256 collateralAmountToWithdraw = 1e18; // ~$202
    uint256 daiToLoan = 2 * 1e20; // $200
    bytes memory makerUniData = abi.encodeWithSelector(
      bytes4(keccak256(bytes("delever(uint256,uint256,uint256,address,address)"))),
      daiToLoan,
      collateralAmountToWithdraw,
      CDP_ID,
      address(MAKER_GUNI_STRATEGY),
      address(EULER_FLASHLOAN_CALLER)
    );

    // Get pre data pre execution
    address urnHandler = MANAGER.urns(CDP_ID);
    (uint256 beforeInk, ) = VAT.urns(bytes32("GUNIV3DAIUSDC2-A"), urnHandler);
    uint256 preDaiBalance = DAI.balanceOf(USER);

    // Execute transaction
    DS_PROXY.execute(
      address(MAKER_GUNI_STRATEGY),
      makerUniData
    );

    // Get pre data post execution
    (uint256 afterInk, ) = VAT.urns(bytes32("GUNIV3DAIUSDC2-A"), urnHandler);
    uint256 postDaiBalance = DAI.balanceOf(USER);

    // Verify LP collateral was decremented
    assertEq(
      beforeInk - collateralAmountToWithdraw,
      afterInk
    );

    // Verify user DAI balance increased
    assertApproxEqAbs(
      postDaiBalance - preDaiBalance,
      2 * 1e18, // $2 DAI difference ($202 collateral withdrawn - $200 flashloan debt repaid)
      2 * 1e18 // +/-2 DAI delta
    );

    // Verify Euler flashloan contract does not have permission to DSProxy
    address postCurrAuthority = address(DSAuth(address(DS_PROXY)).authority());
    DSGuard postGuard = DSGuard(postCurrAuthority);
    assertEq(
      postGuard.canCall(address(EULER_FLASHLOAN_CALLER), address(DS_PROXY), MAKER_GUNI_STRATEGY.EXECUTE_SELECTOR()),
      false
    );

    VM.stopPrank();
  }

  /// @notice Successful lever transaction
  function testLever() public {
    // Delever some to free up debt ceiling
    testDeleverSome();

    VM.startPrank(USER);
    G_UNI_DAIUSDC_POOL_ONE_BPS.approve(address(G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN), type(uint256).max);

    uint256 daiToDeposit = 1e18; // ~$202
    uint256 daiToLoan = 3 * 1e20; // $300
    bytes memory makerUniData = abi.encodeWithSelector(
      bytes4(keccak256(bytes("lever(uint256,uint256,uint256,address,address)"))),
      daiToLoan,
      daiToDeposit,
      CDP_ID,
      address(MAKER_GUNI_STRATEGY),
      address(EULER_FLASHLOAN_CALLER)
    );

    // Get data pre execution
    address urnHandler = MANAGER.urns(CDP_ID);
    (uint256 beforeInk, uint256 beforeArt) = VAT.urns(bytes32("GUNIV3DAIUSDC2-A"), urnHandler);
    uint256 preDaiBalance = DAI.balanceOf(USER);

    // Verify Euler flashloan contract does not have permission to DSProxy
    address preCurrAuthority = address(DSAuth(address(DS_PROXY)).authority());
    DSGuard preGuard = DSGuard(preCurrAuthority);

    // Verify Euler flashloan contract does not have permission to DSProxy
    assertEq(
      preGuard.canCall(address(EULER_FLASHLOAN_CALLER), address(DS_PROXY), MAKER_GUNI_STRATEGY.EXECUTE_SELECTOR()),
      false
    );

    // Execute flashloan
    DS_PROXY.execute(
      address(MAKER_GUNI_STRATEGY),
      makerUniData
    );

    // Get pre data post execution
    (uint256 afterInk, uint256 afterArt) = VAT.urns(bytes32("GUNIV3DAIUSDC2-A"), urnHandler);
    (, uint256 rate, , , ) = VAT.ilks(bytes32("GUNIV3DAIUSDC2-A"));
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
      1e16, // ~$2
      1e16
    );

    // Verify Euler flashloan contract does not have permission to DSProxy
    address postCurrAuthority = address(DSAuth(address(DS_PROXY)).authority());
    DSGuard postGuard = DSGuard(postCurrAuthority);
    assertEq(
      postGuard.canCall(address(EULER_FLASHLOAN_CALLER), address(DS_PROXY), MAKER_GUNI_STRATEGY.EXECUTE_SELECTOR()),
      false
    );

    VM.stopPrank();
  }
}
