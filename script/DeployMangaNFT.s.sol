// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/MangaNFT.sol";
import "src/MonthlyDataUploader.sol";
import "forge-std/Script.sol";

contract DeployMangaNFT is Script {
    function run() public {
        // Provide contract constructor parameters in deployment script / 在部署脚本中提供合约的构造参数
        address _platformAddress = 0x12E2C1e3A8CA617689A4E4E6d6a098Faf08B8189; // Fill in platform address / 填写平台地址
        address _paymentToken = 0x0000000000000000000000000000000000001010; // Fill in payment token address / 填写支付代币地址
        string memory _uri = "https://api.manga.com/metadata/";

        // Start deployment / 启动部署
        vm.startBroadcast(); // Start broadcasting transactions / 开始广播交易

        // Step 1: Deploy MonthlyDataUploader with temporary MangaNFT address / 步骤1：使用临时MangaNFT地址部署MonthlyDataUploader
        MonthlyDataUploader monthlyDataUploader = new MonthlyDataUploader(_platformAddress, address(0));
        console.log("MonthlyDataUploader deployed at:", address(monthlyDataUploader));

        // Step 2: Deploy MangaNFT with MonthlyDataUploader address / 步骤2：使用MonthlyDataUploader地址部署MangaNFT
        MangaNFT mangaNFT = new MangaNFT(_uri, _platformAddress, _paymentToken, address(monthlyDataUploader));
        console.log("MangaNFT deployed at:", address(mangaNFT));

        // Step 3: Update MonthlyDataUploader with correct MangaNFT address / 步骤3：使用正确的MangaNFT地址更新MonthlyDataUploader
        monthlyDataUploader.updateMangaNFTContract(address(mangaNFT));
        console.log("Updated MangaNFT contract address in MonthlyDataUploader");

        vm.stopBroadcast(); // Stop broadcasting transactions / 停止广播交易
    }
}
