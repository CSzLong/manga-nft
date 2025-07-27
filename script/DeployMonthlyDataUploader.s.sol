// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MonthlyDataUploader.sol";

contract DeployMonthlyDataUploader is Script {
    function run(address platformAddress) external {
        vm.startBroadcast();

        // Deploy MonthlyDataUploader with temporary MangaNFT address / 使用临时MangaNFT地址部署MonthlyDataUploader
        MonthlyDataUploader uploader = new MonthlyDataUploader(platformAddress, address(0));

        console.log("MonthlyDataUploader deployed at:", address(uploader));

        vm.stopBroadcast();
    }
}
