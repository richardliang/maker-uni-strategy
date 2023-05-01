# Maker Uniswap Leverage Strategy - DSProxy Scripts

This repo provides a set of smart contract scripts to lever and delever Uniswap LP positions in your Maker CDP. Currently supports:
- Uniswap V2 DAI USDC LP
- Gelato 1bps Uniswap V3 DAI USDC LP

The DAIUSDC LP collaterals in Maker allow up to 50x leverage by borrowing DAI, trading 50% DAI for USDC and depositing the DAIUSDC LP in Maker. Users collect yield in the form of trading fees generated from the leveraged LP. Maker assumes DAI and USDC in the system are $1, so the position can only be liquidated if stability fees > trading fees collected. You can view the Dune dashboard on yields for Uni V2 [here](https://dune.com/Lucianken/uniswap-v2-dai-usdc-leverage-returns), and Gelato 1bps V3 [here](https://dune.com/fb/Yield-with-GUNI-MakerDAO)

However, there is no easy and free way for users to execute this strategy
1. Executing it manually costs hundreds of dollars in ETH L1 gas
2. DeFi Saver users 0x and charges a 0.1% fee for using the service. Additionally, 0x does not route trades through the PSM
3. Maker Multiply charges a 0.1% fee for using the service.

These smart contract scripts improve upon the above by using a flash loan from Euler and free DAI to USDC swaps using the Maker Peg Stability Module.

These scripts are executed via DSProxy

## Test

Tests use [Foundry: Forge](https://github.com/gakonst/foundry).

Install Foundry using the installation steps in the README of the linked repo.

```bash
# Get dependencies
forge update

# Run tests against mainnet fork
forge test --fork-url=YOUR_MAINNET_RPC_URL -vvvv
```

## Deploy and Operate

To get started, deploy the `EulerFlashloanCaller` and `MakerGUniOneBpsLeverageStrategy` or `MakerUniV2LeverageStrategy` depending on which Maker strategy you want to maximize yield using
```bash
# Deploy contracts
forge create --rpc-url YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY EulerFlashLoanCaller
forge create --rpc-url YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY MakerGUniOneBpsLeverageStrategy
forge create --rpc-url YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY MakerUniV2LeverageStrategy
```

Ensure that you've created a CDP and deposited the LP collateral using Oasis UI prior to continuing with the below. The scripts only use flashloans to lever up existing collateral, and does not contain logic to transfer LP collateral from EOA to CDP. Follow the script below to lever up. Check Oasis UI to ensure your position is levered up. Get your CDP ID and DSProxy address from Oasis
```bash
# Get lever calldata first
cast calldata "lever(uint256,uint256,uint256,address,address)" DAI_TO_FLASHLOAN DAI_TO_DEPOSIT YOUR_CDP_ID STRATEGY_ADDRESS EULER_FLASHLOAN_CALLER_ADDRESS

# Execute lever using your ledger as signer
cast send --ledger --hd-path "m/44'/60'/0'/INDEX_OF_LEDGER_ACCOUNT" --flashbots --gas-limit 3000000 --priority-gas-price 5000000000 --gas-price 20000000000 --from YOUR_PUBLIC_EOA_ADDRESS YOUR_DS_PROXY_ADDRESS "execute(address,bytes)" STRATEGY_CONTRACT_ADDRESS CALLDATA_FROM_ABOVE
```

To delever, follow the below commands. The value of the LP tokens in DAI to withdraw must be greater than the DAI you repay for the flashloan
```bash
# Get delever calldata first
cast calldata "delever(uint256,uint256,uint256,address,address)" DAI_TO_REPAY LP_TOKENS_TO_WITHDRAW YOUR_CDP_ID STRATEGY_ADDRESS EULER_FLASHLOAN_CALLER_ADDRESS

# Execute delever using your ledger as signer
cast send --ledger --hd-path "m/44'/60'/0'/INDEX_OF_LEDGER_ACCOUNT" --flashbots --gas-limit 3000000 --priority-gas-price 5000000000 --gas-price 20000000000 --from YOUR_PUBLIC_EOA_ADDRESS YOUR_DS_PROXY_ADDRESS "execute(address,bytes)" STRATEGY_CONTRACT_ADDRESS CALLDATA_FROM_ABOVE
```