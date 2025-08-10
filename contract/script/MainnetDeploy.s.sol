// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LeadershipInbox} from "../src/LeadershipInbox.sol";

contract InboxScript is Script {
    LeadershipInbox public inbox;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // ZK Token in mainnet.
        address acceptedToken = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;

        inbox = new LeadershipInbox(acceptedToken);

        vm.stopBroadcast();
    }
}
