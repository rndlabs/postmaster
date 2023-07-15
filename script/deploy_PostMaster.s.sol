// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {PostMaster} from "../src/PostMaster.sol";

contract DeployPostMaster is Script {
    function setUp() public {}

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        new PostMaster();
        vm.stopBroadcast();
    }
}
