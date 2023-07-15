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

    function test_DoesNotLeaveXDAI() public {
        // Cache the balances
        uint256 xDaiBalanceBefore = address(this).balance;

        // First get a quote
        (uint256 initialBalancePerChunk, uint256 amount) = pm.quotexDAIForTime(18, 30 days);

        // Then purchase the stamp, but send too much xDAI
        pm.purchase{value: amount * 10}(address(this), initialBalancePerChunk, 18, 16, bytes32(0), false);

        // Check the invariants

        // After the stamp has been purchased, we should have less xDAI
        assertEq(address(this).balance, xDaiBalanceBefore - amount);
        // The PostMaster should have no xDAI
        assertEq(address(pm).balance, 0);
        // The PostMaster should have no BZZ
        assertEq(bzz.balanceOf(address(pm)), 0);
    }

    function test_PurchaseStampForAMonth() public {
        // Cache the balances
        uint256 xDaiBalanceBefore = address(this).balance;
        uint256 xDaiBalanceBeforePm = address(pm).balance;
        uint256 bzzBalanceBeforePm = bzz.balanceOf(address(pm));

        // First get a quote
        (uint256 initialBalancePerChunk, uint256 amount) = pm.quotexDAIForTime(18, 30 days);

        // Then purchase the stamp
        pm.purchase{value: amount}(address(this), initialBalancePerChunk, 18, 16, bytes32(0), false);

        // Check invariants
        // After the stamp has been purchased, we should have less xDAI
        assertEq(address(this).balance, xDaiBalanceBefore - amount);
        // The PostMaster should have no xDAI
        assertEq(address(pm).balance, xDaiBalanceBeforePm);
        // The PostMaster should have no BZZ
        assertEq(bzz.balanceOf(address(pm)), bzzBalanceBeforePm);
    }

    function test_PurchaseManyForAMonth() public {
        // Cache the balances
        uint256 xDaiBalanceBefore = address(this).balance;
        uint256 xDaiBalanceBeforePm = address(pm).balance;
        uint256 bzzBalanceBeforePm = bzz.balanceOf(address(pm));

        // Create dogfooding array of depths and nonces
        uint8[] memory depths = new uint8[](10);
        // Fill the array with 18s
        for (uint8 i = 0; i < depths.length; i++) {
            depths[i] = 18 + i;
        }
        bytes32[] memory nonces = new bytes32[](10);
        for (uint8 i = 0; i < nonces.length; i++) {
            nonces[i] = bytes32(uint256(keccak256(abi.encodePacked(block.timestamp, i))));
        }

        // First get a quote
        (uint256 initialBalancePerChunk, uint256 xDaiRequired, uint256 bzzRequired) = pm.quotexDAIForTimeMany(depths, 30 days);

        // Then purchase the stamps
        pm.purchaseMany{value: xDaiRequired}(address(this), initialBalancePerChunk, depths, 16, nonces, false, bzzRequired);

        // Check the invariants

        // After the stamp has been purchased, we should have less xDAI
        assertEq(address(this).balance, xDaiBalanceBefore - xDaiRequired);
        // The PostMaster should have no xDAI
        assertEq(address(pm).balance, xDaiBalanceBeforePm);
        // The PostMaster should have no BZZ
        assertEq(bzz.balanceOf(address(pm)), bzzBalanceBeforePm);
    }

    function test_QuotexDAI() public {
        // First get a normal quote
        (, uint256 xdaiRequired) = pm.quotexDAI(500_000, 18);

        // Then get a quote for many, but for the depths use the same depth
        // and an array of 1
        uint8[] memory depths = new uint8[](1);
        depths[0] = 18;
        (, uint256 xdaiRequiredMany) = pm.quotexDAIMany(500_000, depths);

        // Check the invariants
        assertEq(xdaiRequired, xdaiRequiredMany);
    }

    receive() external payable {}
}
