// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MonthlyDataUploader is Ownable {
    address public platformAddress;

    // 月度数据结构
    struct CreatorMonthlyData {
        address creator;
        uint256 monthlyPublished; // 当月发布的数量
        uint256 totalPublished; // 总发布的数量
        uint256 monthlyAcquired; // 当月获得总量
        uint256 currentHeld; // 现有总量
        uint256 timestamp; // 上传时间戳
    }

    struct InvestorMonthlyData {
        address investor;
        uint256 monthlyAcquired; // 当月获得总量
        uint256 totalAcquired; // 总获得量
        uint256 currentHeld; // 现有量
        uint256 timestamp; // 上传时间戳
    }

    // 存储月度数据
    mapping(uint256 => CreatorMonthlyData[]) public monthlyCreatorData; // 年月 => 创作者数据数组
    mapping(uint256 => InvestorMonthlyData[]) public monthlyInvestorData; // 年月 => 投资者数据数组

    // 用于追踪创作者的数据
    mapping(address => uint256) public creatorTotalPublished; // 创作者 => 总发布数量
    mapping(address => uint256) public creatorTotalAcquired; // 创作者 => 总获得数量
    mapping(address => mapping(uint256 => uint256)) public creatorMonthlyPublished; // 创作者 => 年月 => 当月发布数量
    mapping(address => mapping(uint256 => uint256)) public creatorMonthlyAcquired; // 创作者 => 年月 => 当月获得数量

    // 用于追踪投资者的数据
    mapping(address => uint256) public investorTotalAcquired; // 投资者 => 总获得数量
    mapping(address => mapping(uint256 => uint256)) public investorMonthlyAcquired; // 投资者 => 年月 => 当月获得数量

    // 记录所有创作者和投资者地址
    mapping(address => bool) public isCreator;
    mapping(address => bool) public isInvestor;
    address[] public creators;
    address[] public investors;

    event MonthlyDataUploaded(uint256 indexed yearMonth, uint256 creatorCount, uint256 investorCount);
    event CreatorDataUploaded(
        uint256 indexed yearMonth,
        address indexed creator,
        uint256 monthlyPublished,
        uint256 totalPublished,
        uint256 monthlyAcquired,
        uint256 currentHeld
    );
    event InvestorDataUploaded(
        uint256 indexed yearMonth,
        address indexed investor,
        uint256 monthlyAcquired,
        uint256 totalAcquired,
        uint256 currentHeld
    );
    event CreatorNFTPublished(
        address indexed creator, uint256 publishedCount, uint256 totalPublished, uint256 acquiredCount
    );
    event InvestorNFTAcquired(address indexed investor, uint256 acquiredCount, uint256 totalAcquired);

    modifier onlyPlatform() {
        require(msg.sender == platformAddress, "Only platform can call");
        _;
    }

    modifier onlyEndOfMonth() {
        uint256 currentTime = block.timestamp;
        // 简化的月末检查：每30天的最后一天
        uint256 dayInMonth = (currentTime / 1 days) % 30;
        require(dayInMonth >= 28, "Can only upload near end of month");
        _;
    }

    constructor(address _platformAddress) Ownable(msg.sender) {
        require(_platformAddress != address(0), "Invalid Platform Address");
        platformAddress = _platformAddress;
    }

    // 获取当前年月 (格式: YYYYMM)
    function getCurrentYearMonth() public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        // 简化的年月计算
        uint256 year = 2024 + ((timestamp - 1704067200) / (365 days)); // 从2024年1月1日开始
        uint256 month = (((timestamp - 1704067200) % (365 days)) / (30 days)) + 1;
        if (month > 12) month = 12;
        return year * 100 + month;
    }

    // 记录创作者发布NFT信息
    function recordCreatorPublish(address creator, uint256 publishedCount, uint256 acquiredCount)
        external
        onlyPlatform
    {
        require(creator != address(0), "Invalid creator address");

        // 如果不是创作者，先注册为创作者
        if (!isCreator[creator]) {
            isCreator[creator] = true;
            creators.push(creator);
        }

        uint256 currentYearMonth = getCurrentYearMonth();

        // 更新当月发布数量
        creatorMonthlyPublished[creator][currentYearMonth] += publishedCount;

        // 更新总发布数量
        creatorTotalPublished[creator] += publishedCount;

        // 更新当月获得数量（平台mint给作者的数量）
        creatorMonthlyAcquired[creator][currentYearMonth] += acquiredCount;

        // 更新总获得数量
        creatorTotalAcquired[creator] += acquiredCount;

        emit CreatorNFTPublished(creator, publishedCount, creatorTotalPublished[creator], acquiredCount);
    }

    // 记录投资者获得NFT信息
    function recordInvestorAcquire(address investor, uint256 acquiredCount) external onlyPlatform {
        require(investor != address(0), "Invalid investor address");

        // 如果不是投资者，先注册为投资者
        if (!isInvestor[investor]) {
            isInvestor[investor] = true;
            investors.push(investor);
        }

        uint256 currentYearMonth = getCurrentYearMonth();

        // 更新当月获得数量
        investorMonthlyAcquired[investor][currentYearMonth] += acquiredCount;

        // 更新总获得数量
        investorTotalAcquired[investor] += acquiredCount;

        emit InvestorNFTAcquired(investor, acquiredCount, investorTotalAcquired[investor]);
    }

    // 上传月度数据 (只能在月末执行)
    function uploadMonthlyData() external onlyOwner onlyEndOfMonth {
        uint256 currentYearMonth = getCurrentYearMonth();

        // 上传创作者数据
        _uploadCreatorData(currentYearMonth);

        // 上传投资者数据
        _uploadInvestorData(currentYearMonth);

        emit MonthlyDataUploaded(currentYearMonth, creators.length, investors.length);
    }

    // 强制上传月度数据 (紧急情况下使用，跳过月末检查)
    function forceUploadMonthlyData() external onlyOwner {
        uint256 currentYearMonth = getCurrentYearMonth();

        // 上传创作者数据
        _uploadCreatorData(currentYearMonth);

        // 上传投资者数据
        _uploadInvestorData(currentYearMonth);

        emit MonthlyDataUploaded(currentYearMonth, creators.length, investors.length);
    }

    // 指定年月上传数据
    function uploadDataForMonth(uint256 yearMonth) external onlyOwner {
        // 上传创作者数据
        _uploadCreatorData(yearMonth);

        // 上传投资者数据
        _uploadInvestorData(yearMonth);

        emit MonthlyDataUploaded(yearMonth, creators.length, investors.length);
    }

    // 内部函数：上传创作者数据
    function _uploadCreatorData(uint256 yearMonth) internal {
        for (uint256 i = 0; i < creators.length; i++) {
            address creator = creators[i];

            // 获取当月发布数量
            uint256 monthlyPublished = creatorMonthlyPublished[creator][yearMonth];

            // 获取总发布数量
            uint256 totalPublished = creatorTotalPublished[creator];

            // 获取当月获得数量
            uint256 monthlyAcquired = creatorMonthlyAcquired[creator][yearMonth];

            // 获取创作者当前持有的NFT总数
            uint256 currentHeld = 0; // This will need to be implemented based on how currentHeld is calculated

            CreatorMonthlyData memory data = CreatorMonthlyData({
                creator: creator,
                monthlyPublished: monthlyPublished,
                totalPublished: totalPublished,
                monthlyAcquired: monthlyAcquired,
                currentHeld: currentHeld,
                timestamp: block.timestamp
            });

            monthlyCreatorData[yearMonth].push(data);

            emit CreatorDataUploaded(yearMonth, creator, monthlyPublished, totalPublished, monthlyAcquired, currentHeld);
        }
    }

    // 内部函数：上传投资者数据
    function _uploadInvestorData(uint256 yearMonth) internal {
        for (uint256 i = 0; i < investors.length; i++) {
            address investor = investors[i];

            // 获取当月获得数量
            uint256 monthlyAcquired = investorMonthlyAcquired[investor][yearMonth];

            // 获取总获得数量
            uint256 totalAcquired = investorTotalAcquired[investor];

            // 获取投资者当前持有的NFT总数
            uint256 currentHeld = 0; // This will need to be implemented based on how currentHeld is calculated

            InvestorMonthlyData memory data = InvestorMonthlyData({
                investor: investor,
                monthlyAcquired: monthlyAcquired,
                totalAcquired: totalAcquired,
                currentHeld: currentHeld,
                timestamp: block.timestamp
            });

            monthlyInvestorData[yearMonth].push(data);

            emit InvestorDataUploaded(yearMonth, investor, monthlyAcquired, totalAcquired, currentHeld);
        }
    }

    // 手动添加创作者地址
    function addCreator(address creator) external onlyOwner {
        require(creator != address(0), "Invalid creator address");
        if (!isCreator[creator]) {
            isCreator[creator] = true;
            creators.push(creator);
        }
    }

    // 手动添加投资者地址
    function addInvestor(address investor) external onlyOwner {
        require(investor != address(0), "Invalid investor address");
        if (!isInvestor[investor]) {
            isInvestor[investor] = true;
            investors.push(investor);
        }
    }

    // 批量添加创作者
    function addCreators(address[] calldata _creators) external onlyOwner {
        for (uint256 i = 0; i < _creators.length; i++) {
            if (_creators[i] != address(0) && !isCreator[_creators[i]]) {
                isCreator[_creators[i]] = true;
                creators.push(_creators[i]);
            }
        }
    }

    // 批量添加投资者
    function addInvestors(address[] calldata _investors) external onlyOwner {
        for (uint256 i = 0; i < _investors.length; i++) {
            if (_investors[i] != address(0) && !isInvestor[_investors[i]]) {
                isInvestor[_investors[i]] = true;
                investors.push(_investors[i]);
            }
        }
    }

    // 查询某月的创作者数据
    function getCreatorDataByMonth(uint256 yearMonth) external view returns (CreatorMonthlyData[] memory) {
        return monthlyCreatorData[yearMonth];
    }

    // 查询某月的投资者数据
    function getInvestorDataByMonth(uint256 yearMonth) external view returns (InvestorMonthlyData[] memory) {
        return monthlyInvestorData[yearMonth];
    }

    // 查询特定创作者某月的数据
    function getCreatorMonthlyData(address creator, uint256 yearMonth)
        external
        view
        returns (CreatorMonthlyData memory)
    {
        CreatorMonthlyData[] memory data = monthlyCreatorData[yearMonth];
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i].creator == creator) {
                return data[i];
            }
        }
        revert("Creator data not found for specified month");
    }

    // 查询特定投资者某月的数据
    function getInvestorMonthlyData(address investor, uint256 yearMonth)
        external
        view
        returns (InvestorMonthlyData memory)
    {
        InvestorMonthlyData[] memory data = monthlyInvestorData[yearMonth];
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i].investor == investor) {
                return data[i];
            }
        }
        revert("Investor data not found for specified month");
    }

    // 获取所有注册的创作者
    function getAllCreators() external view returns (address[] memory) {
        return creators;
    }

    // 获取所有注册的投资者
    function getAllInvestors() external view returns (address[] memory) {
        return investors;
    }

    // 获取创作者的统计信息
    function getCreatorStats(address creator)
        external
        view
        returns (uint256 totalPublished, uint256 totalAcquired, uint256 currentHeld)
    {
        totalPublished = creatorTotalPublished[creator];
        totalAcquired = creatorTotalAcquired[creator];
        currentHeld = 0; // This will need to be implemented based on how currentHeld is calculated
    }

    // 获取投资者的统计信息
    function getInvestorStats(address investor) external view returns (uint256 totalAcquired, uint256 currentHeld) {
        totalAcquired = investorTotalAcquired[investor];
        currentHeld = 0; // This will need to be implemented based on how currentHeld is calculated
    }

    // 获取创作者某月的发布和获得数量
    function getCreatorMonthlyStats(address creator, uint256 yearMonth)
        external
        view
        returns (uint256 monthlyPublished, uint256 monthlyAcquired)
    {
        monthlyPublished = creatorMonthlyPublished[creator][yearMonth];
        monthlyAcquired = creatorMonthlyAcquired[creator][yearMonth];
    }

    // 获取投资者某月的获得数量
    function getInvestorMonthlyStats(address investor, uint256 yearMonth)
        external
        view
        returns (uint256 monthlyAcquired)
    {
        monthlyAcquired = investorMonthlyAcquired[investor][yearMonth];
    }

    // 批量获取多个月的创作者数据
    function getCreatorDataByMonths(uint256[] calldata yearMonths)
        external
        view
        returns (CreatorMonthlyData[][] memory)
    {
        CreatorMonthlyData[][] memory results = new CreatorMonthlyData[][](yearMonths.length);
        for (uint256 i = 0; i < yearMonths.length; i++) {
            results[i] = monthlyCreatorData[yearMonths[i]];
        }
        return results;
    }

    // 批量获取多个月的投资者数据
    function getInvestorDataByMonths(uint256[] calldata yearMonths)
        external
        view
        returns (InvestorMonthlyData[][] memory)
    {
        InvestorMonthlyData[][] memory results = new InvestorMonthlyData[][](yearMonths.length);
        for (uint256 i = 0; i < yearMonths.length; i++) {
            results[i] = monthlyInvestorData[yearMonths[i]];
        }
        return results;
    }

    // 更新平台地址
    function updatePlatformAddress(address newPlatformAddress) external onlyOwner {
        require(newPlatformAddress != address(0), "Invalid platform address");
        platformAddress = newPlatformAddress;
    }

    // 清除某月的数据 (紧急情况使用)
    function clearMonthlyData(uint256 yearMonth) external onlyOwner {
        delete monthlyCreatorData[yearMonth];
        delete monthlyInvestorData[yearMonth];
    }

    // 移除创作者
    function removeCreator(address creator) external onlyOwner {
        require(isCreator[creator], "Address is not a creator");
        isCreator[creator] = false;

        // 从数组中移除
        for (uint256 i = 0; i < creators.length; i++) {
            if (creators[i] == creator) {
                creators[i] = creators[creators.length - 1];
                creators.pop();
                break;
            }
        }
    }

    // 移除投资者
    function removeInvestor(address investor) external onlyOwner {
        require(isInvestor[investor], "Address is not an investor");
        isInvestor[investor] = false;

        // 从数组中移除
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == investor) {
                investors[i] = investors[investors.length - 1];
                investors.pop();
                break;
            }
        }
    }
}
