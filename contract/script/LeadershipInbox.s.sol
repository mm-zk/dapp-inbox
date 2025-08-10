// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LeadershipInbox} from "../src/LeadershipInbox.sol";

contract InboxScript is Script {
    LeadershipInbox public inbox;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address acceptedToken = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

        inbox = new LeadershipInbox(acceptedToken);

        vm.stopBroadcast();
    }
}
