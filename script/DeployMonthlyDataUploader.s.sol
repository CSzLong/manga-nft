// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MonthlyDataUploader.sol";

contract DeployMonthlyDataUploader is Script {
    function run(address platformAddress, address mangaNFTAddress) external {
        vm.startBroadcast();
        
        MonthlyDataUploader uploader = new MonthlyDataUploader(
            platformAddress,
            mangaNFTAddress
        );

        console.log("MonthlyDataUploader deployed at:", address(uploader));

        vm.stopBroadcast();
    }
}
