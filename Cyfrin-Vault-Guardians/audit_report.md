## Highs

### [H-1] Profits can be stolen due to lack of slippage protection in `UniswapAdapter::_uniswapInvest`

**Description:** In `UniswapAdapter::_uniswapInvest` while swapping tokens on Uniswap this is set:
```c
uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
    amountIn: amountOfTokenToSwap,
    // how much of the minimum number of tokens it expects to return
    amountOutMin: 0,
    path: s_pathArray,
    to: address(this),
    // when the transaction should expire?
    deadline: block.timestamp
})
```
We are expecting minimum 0 tokens in return, also the deadline is set to `block.timestamp`

**Impact:** 
- Due to the minimum amount set, anyone can pull a flashloan and swap on Uniswap to tank the price before the swap happens, resulting in the protocol executing the swap at an unfavorable rate. Getting a very return
- Due to lack of deadline, the node who gets this transaction could hold the transaction until they are able to profit from the guaranteed swap.

**Proof of Concept:**
1. User deposits in a vault which has Uniswap, `UniswapAdapter::_uniswapInvest` gets called
2. This txn can be seen on the mempool by anyone(flashbots)
3. A flashbot can take a big flashloan and tank up the price of assets
4. This will result in the protocol getting as little funds as possible as the minimum limit is set to 0.

**Recommended Mitigation:** 
1. Add a deadline to the Uniswap swap
2. Have a minimum amount set in `amountOutMin` , gathering price info from Chainlink

## Mediums

### [M-1] `_aaveDivest` declares a return value but fails to capture the actual amount from `i_aavePool.withdraw()`, causing callers to receive 0 instead, which breaks upstream accounting and vault balance tracking.

**Description:** The function `AaveAdapter::_aaveDivest` is supposed to return `amountOfAssetReturned` but it is not returned.

```c
function _aaveDivest(IERC20 token, uint256 amount) internal returns (uint256 amountOfAssetReturned) {
    // not assigned
    i_aavePool.withdraw({
        asset: address(token),
        amount: amount,
        to: address(this)
    });
}
```

**Impact:** Incorrect data obtained, potentially breaking accounting logic


**Recommended Mitigation:** 
```c
function _aaveDivest(IERC20 token, uint256 amount) internal returns (uint256 amountOfAssetReturned) {
    amountOfAssetReturned = i_aavePool.withdraw({
        asset: address(token),
        amount: amount,
        to: address(this)
    });
}
```

### [M-2] Fees not collected for becoming a Guardian in `VaultGuardianBase::becomeGuardian`

**Description:** According to the function defiinition,to be a vault guardian one has to send an ETH amount equal to the fee `0.1 ether`, and a WETH amount equal to the stake price `10 ether`. The stake price is collected but no fees is collected.

**Impact:** Loss of revenue/fees for the protocol

**Proof of Concept:**
```c
function testBecomeGuardianNoFees() public {
    // they have to send an ETH amount equal to the fee 0.1 ether
    // and a WETH amount equal to the stake price 10 ether
    uint256 initialBalance = guardian.balance;

    mintAmount = 10 ether;
    weth.mint(mintAmount, guardian);
    vm.startPrank(guardian);
    weth.approve(address(vaultGuardians), mintAmount);
    vaultGuardians.becomeGuardian(allocationData);
    vm.stopPrank();

    uint256 finalBalance = guardian.balance;
    // they should have paid the 0.1 ether fee, but they didn't pay anything
    assertEq(initialBalance, finalBalance);
}
```

**Recommended Mitigation:** A simple check like this ensures that fees is paid:
```c
function becomeGuardian(AllocationData memory wethAllocationData) external returns (address) {
    if(msg.value<GUARDIAN_FEE){
        revert VaultGuardiansBase__FeeTooSmall(msg.value,GUARDIAN_FEE);
    }
}
```

## Lows

### [L-1] Incorrect vault name and symbol passed in `VaultGuardianBase::becomeTokenGuardian`

**Description:**
```c
else if (address(token) == address(i_tokenTwo)) {
    tokenVault =
    new VaultShares(IVaultShares.ConstructorData({
        asset: token,
        // should have been TOKEN_TWO_VAULT_NAME and TOKEN_TWO_VAULT_SYMBOL
        vaultName: TOKEN_ONE_VAULT_NAME,
        vaultSymbol: TOKEN_ONE_VAULT_SYMBOL,
    ...})
}
```

**Recommended Mitigation:** 
```c
else if (address(token) == address(i_tokenTwo)) {
    tokenVault =
    new VaultShares(IVaultShares.ConstructorData({
        asset: token,
        vaultName: TOKEN_TWO_VAULT_NAME,
        vaultSymbol: TOKEN_TWO_VAULT_SYMBOL,
    ...})
}
```

## Informationals

### [I-1] Incorrect params passed while emitting `VaultGuardians__UpdatedStakePrice` event in `VaultGuardians::updateGuardianStakePrice`

**Description:** `newStakePrice` is passed twice while emitting the event. `s_guardianStakePrice=newStakePrice`.
```c
function updateGuardianStakePrice(uint256 newStakePrice) external onlyOwner {
    s_guardianStakePrice = newStakePrice;
    // newStakePrice twice
    emit VaultGuardians__UpdatedStakePrice(s_guardianStakePrice, newStakePrice);
}
```

**Recommended Mitigation:** 
```c
function updateGuardianStakePrice(uint256 newStakePrice) external onlyOwner {
    emit VaultGuardians__UpdatedStakePrice(s_guardianStakePrice, newStakePrice);
    s_guardianStakePrice = newStakePrice;
}
```

### [I-2] Incorrect event `VaultGuardians__UpdatedStakePrice` emitted in `VaultGuardians::updateGuardianAndDaoCut`

**Description:**
```c
function updateGuardianAndDaoCut(uint256 newCut) external onlyOwner {
    s_guardianAndDaoCut = newCut;
    // incorrect event
    emit VaultGuardians__UpdatedStakePrice(s_guardianAndDaoCut, newCut);
}
```

**Recommended Mitigation:** 
```c
function updateGuardianAndDaoCut(uint256 newCut) external onlyOwner {
    emit VaultGuardians__UpdatedGuardianAndDaoCut(s_guardianAndDaoCut, newCut);
    s_guardianAndDaoCut = newCut;
}
```

### [I-3] Safe approval not used in `AaveAdapter::_aaveInvest`

**Description:** This won't cause any issue with USDC or LINK, still a safe practice
```c
function _aaveInvest(IERC20 asset, uint256 amount) internal {
    // .approve used instead of .safeApprove
    bool succ = asset.approve(address(i_aavePool), amount);
    ...
}
```

**Recommended Mitigation:** 
```c
function _aaveInvest(IERC20 asset, uint256 amount) internal {
    bool succ = asset.safeApprove(address(i_aavePool), amount);
    ...
}
```