// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/PostMaster.sol";
import "solmate/tokens/ERC20.sol";

contract PostMasterTest is Test {
    PostMaster public pm;
    // The bridged BZZ token on Gnosis Chain
    ERC20 private constant bzz = ERC20(0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da);

    function setUp() public {
        pm = new PostMaster();
    }

    function test_PurchaseStampForAMonth() public {
        // First get a quote
        (uint256 initialBalancePerChunk, uint256 amount) = pm.quotexDAIForTime(18, 30 days);
        uint256 xDaiBalanceBefore = address(this).balance;
        uint256 xDaiBalanceBeforePm = address(pm).balance;
        uint256 bzzBalanceBeforePm = bzz.balanceOf(address(pm));

        // Then purchase the stamp
        pm.purchase{value: amount}(
            address(this),
            initialBalancePerChunk,
            18,
            16,
            bytes32(0),
            false
        );

        // After the stamp has been purchased, we should have less xDAI
        assertEq(address(this).balance, xDaiBalanceBefore - amount);
        // The PostMaster should have no xDAI
        assertEq(address(pm).balance, xDaiBalanceBeforePm);
        // The PostMaster should have no BZZ
        assertEq(bzz.balanceOf(address(pm)), bzzBalanceBeforePm);
    }

    function test_noop() public {
        assertEq(true, true);
    }

    // function testIncrement() public {
    //     avatar.increment();
    //     assertEq(avatar.number(), 1);
    // }

    // function testSetNumber(uint256 x) public {
    //     avatar.setNumber(x);
    //     assertEq(avatar.number(), x);
    // }
}
