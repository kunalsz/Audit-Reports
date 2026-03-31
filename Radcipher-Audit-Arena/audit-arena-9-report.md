# [C-1] Push-based refunds allow one user to block all refunds by rejecting ETH

## Summary
In the function `BatchRefundCrowdfund::processRefunds`, if any one user rejects ETH  the entire batch reverts and refunds get stuck forever. 

## Root Cause
Using a push based model with a reverting external call inside a loop and trusting that the user will definitely accept the incoming ETH
```solidity
(bool ok, ) = user.call{value: amount}("");
require(ok, "Refund failed");
```

## Attack Path
1. A malicious user with no receive/fallback function contributes some funds in the contract
2. The flow goes as usual and other people also contribute
3. When the time/situation comes to process refunds refunds get stuck on the malicious user
4. Funds of other folks get stuck

## Proof of Concept
```solidity
function testBreakRefund() public contributed {
    // rn the fund has 3 ether from userA, goal is 10 ether, so goal missed
    EvilUser evil = new EvilUser();
    vm.deal(address(evil), 1 ether);

    vm.prank(address(evil));
    fund.contribute{value: 1 ether}(); // 4 ether now

    vm.prank(userB); // fails
    fund.contribute{value: 1 ether}(); // 5 ether now

    vm.prank(userC); // fails
    fund.contribute{value: 1 ether}(); // 6 ether now

    // warp to after deadline, goal missed
    vm.warp(block.timestamp + 300);

    // finalize the campaign
    fund.finalize();

    // reverts, only userA gets refunds
    fund.processRefunds(10);
}

contract EvilUser {}
```

## Recommened Fix
- Using pull based method instead of push based would be better
- or using non blocking refunds
```solidity
(bool ok, ) = user.call{value: amount}("");
if (!ok) {
    contributed[user] = amount; // restore OR track separately
}
```

# [M-1] Strict '>' check in finalize prevents withdrawal even when goal is met

## Summary
Incorrent success condition ">" instead of ">=" is logically wrong for crowdfunding systems. Funds get stuck even when condition is met.

## Root cause
In the function `BatchRefundCrowdfund::finalize` :
```solidity
if (totalRaised > goal) {
    successful = true;
}
```

## Attack Path
1. Contributing exact amount of funds

## Proof of Concept
```solidity
// with goal = 10 ether;
function testWithdrawForExactGoal() public {
    vm.prank(userC);
    fund.contribute{value: 10 ether}();

    // warp to after deadline, goal met
    vm.warp(block.timestamp + 300);

    // finalize the campaign
    fund.finalize();

    // will revert as goal was 10 ether
    fund.creatorWithdraw();
}
```

## Recommened Fix
In `finalize` :
```solidity
if (totalRaised >= goal) {
    successful = true;
}
```

# [H-1] Missing deadline check in contribute allows late contributions, breaking campaign logic

## Summary
Missing deadline check in `BatchRefundCrowdfund::contribute` allows users to contribute to the funds even after deadline. This breaks the core invariant of crowdfunding. (Anyone can contribute ETH "until" deadline)

## Root Cause
```solidity
function contribute() external payable {
    // no deadline check present
    require(msg.value > 0, "No ETH");
    ...
}
```

## Attack Path
- After the deadline has passed anyone can contribute

## Proof of Concept
```solidity
// with deadline set to 200 secs
function testContributeAfterDeadline() public{
    vm.warp(block.timestamp + 300);
    vm.prank(userA);
    // passes, no revert ! can contribute after deadline
    fund.contribute{value: 1 ether}();
}
```

## Recommended Fix
```solidity
function contribute() external payable {
    // no deadline check present
    require(msg.value > 0, "No ETH");
    require(block.timestamp < deadline, "Ended");
    ...
}
```

# [L-1] totalRaised not decremented on refunds leads to incorrect accounting after failed campaigns

## Summary
After refunds, `totalRaised` still reflects original amount. This can confuse later logic or accounting.

## Root Cause
In `processRefunds` :
```solidity
if (amount > 0) {
    contributed[user] = 0;
    // amount is not deducted to totalRaised
    (bool ok, ) = user.call{value: amount}("");
    require(ok, "Refund failed");
}
```

## Proof of Concept
```solidity
function testTotalRaisedRemainsAfterRefunds() public contributed {
    // rn the fund has 3 ether from userA, goal is 10 ether, so goal missed
    assert(userA.balance == 2 ether);
    // after deadline
    vm.warp(block.timestamp + 300);

    fund.finalize();
    fund.processRefunds(10);

    // total raised is still 3 ether, even after refunds
    assertEq(fund.totalRaised(), 3 ether);
    // amount got refunded
    assert(userA.balance == 5 ether);
}
```

## Recommended Fix
In `processRefunds` :
```solidity
if (amount > 0) {
    contributed[user] = 0;
    totalRaised -= amount;
    (bool ok, ) = user.call{value: amount}("");
    require(ok, "Refund failed");
}
```