// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IDebtToken } from "./IDebtToken.sol";
import { IEulerExec } from "./IEulerExec.sol";
import { IERC20 } from "./IERC20.sol";
import "./MakerInterfaces.sol";
import "./GUniInterfaces.sol";

abstract contract GUniStrategyHelper {
  IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
  
  IGUniRouter public constant G_UNI_ROUTER = IGUniRouter(0x513E0a261af2D33B46F98b81FED547608fA2a03d);
  IGUniPool public constant G_UNI_DAIUSDC_POOL_ONE_BPS = IGUniPool(0x50379f632ca68D36E50cfBC8F78fe16bd1499d1e);
  IGUniPool public constant G_UNI_DAIUSDC_POOL_FIVE_BPS = IGUniPool(0xAbDDAfB225e10B90D798bB8A886238Fb835e2053);

  DaiJoinLike public constant DAI_JOIN = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
  JugLike public constant JUG = JugLike(0x19c0976f590D67707E62397C87829d896Dc0f1F1);
  ManagerLike public constant MANAGER = ManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
  VatLike public constant VAT = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
  DssPsmLike public constant DSS_PSM = DssPsmLike(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A);
  GemJoinLike public constant USDC_PSM_JOIN = GemJoinLike(0x0A59649758aa4d66E25f08Dd01271e891fe52199);
  GemJoinLike public constant G_UNI_DAIUSDC_POOL_ONE_BPS_JOIN = GemJoinLike(0xA7e4dDde3cBcEf122851A7C8F7A55f23c0Daf335);
  GemJoinLike public constant G_UNI_DAIUSDC_POOL_FIVE_BPS_JOIN = GemJoinLike(0xbFD445A97e7459b0eBb34cfbd3245750Dba4d7a4);

  IEulerExec public constant EULER_EXEC = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);
  address public constant EULER_MAIN = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
  IDebtToken public constant DAI_DEBT_TOKEN = IDebtToken(0x6085Bc95F506c326DCBCD7A6dd6c79FBc18d4686);

  uint256 constant RAY = 10 ** 27;

  error IntOverflow();

  struct FlashLoanParams {
    uint256 daiLoanAmount;
    uint256 daiToDepositOrLiquidityToWithdraw;
    uint256 cdp;
    address dsProxy;
    address makerUniStrategy;
    address eulerFlashLoanCaller;
    address payer;
    bool isLever;
  }
}