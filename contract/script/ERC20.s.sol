// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "../src/ERC20.sol";

contract InboxScript is Script {
    ERC20 public token;

    function setUp() public {
    }

    function run() public {
        vm.startBroadcast();
        token = new ERC20("Test Token", "TT", 1000000 * 10 ** 18);


        vm.stopBroadcast();
    }
}
