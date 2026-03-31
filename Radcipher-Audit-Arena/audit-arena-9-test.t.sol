// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BatchRefundCrowdfund} from "src/AuditArena9.sol";
import {Test,console2} from "forge-std/Test.sol";

contract TestBatchRefundCrowdfund is Test {
    BatchRefundCrowdfund fund;
    address userA = makeAddr("userA");
    address userB = makeAddr("userB");
    address userC = makeAddr("userC");

    receive() external payable {}

    function setUp() public{
        fund = new BatchRefundCrowdfund(10 ether,200);

        vm.deal(userA, 5 ether);
        vm.deal(userB, 10 ether);
        vm.deal(userC, 50 ether);
    }

    modifier contributed() {
        vm.prank(userA);
        fund.contribute{value: 3 ether}();
        _;
    }

    // contribution tests
    function testContributeBeforeDeadline() public{
        vm.prank(userA);
        fund.contribute{value: 3 ether}();

        vm.prank(userB);
        fund.contribute{value: 7 ether}();

        assertEq(fund.totalRaised(), 10 ether);
        assertEq(fund.contributed(userA), 3 ether);
        assertEq(fund.contributed(userB), 7 ether);
    }

    function testContributeAfterDeadline() public{
        vm.warp(block.timestamp + 300);
        vm.prank(userA);
        // passes, no revert ! can contribute after deadline
        fund.contribute{value: 1 ether}();

    }

    function testRefund() public contributed {
        // warp to after deadline, goal missed
        vm.warp(block.timestamp + 300);

        fund.finalize();

        vm.expectRevert();
        fund.creatorWithdraw();

        // process refunds in batch
        fund.processRefunds(10);
    }

    function testWithdrawForExactGoal() public {
        vm.prank(userC);
        fund.contribute{value: 10 ether}();

        vm.warp(block.timestamp + 300);

        fund.finalize();

        // creator should be able to withdraw since goal met, but reverts
        fund.creatorWithdraw();
    }

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
}

contract EvilUser {
    
}