// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/MangaNFT.sol";
import "forge-std/Script.sol";

contract DeployMangaNFT is Script {
    function run() public {
        // 在部署脚本中，提供合约的构造参数
        address _platformAddress = 0x12E2C1e3A8CA617689A4E4E6d6a098Faf08B8189;  // 填写平台地址
        address _paymentToken = 0x0000000000000000000000000000000000001010;  // 填写支付代币地址
        string memory _uri = "https://api.manga.com/metadata/";
        
        // 启动部署
        vm.startBroadcast();  // 开始广播交易
        new MangaNFT(_uri, _platformAddress, _paymentToken);
        vm.stopBroadcast();  // 停止广播交易
    }
}
