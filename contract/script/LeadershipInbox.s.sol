// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LeadershipInbox} from "../src/LeadershipInbox.sol";

contract InboxScript is Script {
    LeadershipInbox public inbox;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        inbox = new LeadershipInbox();

        vm.stopBroadcast();
    }
}
