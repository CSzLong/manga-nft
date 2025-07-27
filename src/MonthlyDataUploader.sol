// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract MonthlyDataUploader is Ownable {
    address public platformAddress;
    IERC1155 public mangaNFTContract;

    // Monthly data structures / 月度数据结构
    struct CreatorMonthlyData {
        address creator;
        uint256 monthlyPublished; // Monthly published count / 当月发布的数量
        uint256 totalPublished; // Total published count / 总发布的数量
        uint256 monthlyAcquired; // Monthly acquired count / 当月获得总量
        uint256 currentHeld; // Current held count / 现有总量
        uint256 timestamp; // Upload timestamp / 上传时间戳
    }

    struct InvestorMonthlyData {
        address investor;
        uint256 monthlyAcquired; // Monthly acquired count / 当月获得总量
        uint256 totalAcquired; // Total acquired count / 总获得量
        uint256 currentHeld; // Current held count / 现有量
        uint256 timestamp; // Upload timestamp / 上传时间戳
    }

    // Token tracking structures / NFT追踪结构
    struct NFTOwner {
        address owner;
        uint256 balance;
    }

    // Monthly data storage / 月度数据存储
    mapping(uint256 => CreatorMonthlyData[]) public monthlyCreatorData; // YearMonth => Creator data array / 年月 => 创作者数据数组
    mapping(uint256 => InvestorMonthlyData[]) public monthlyInvestorData; // YearMonth => Investor data array / 年月 => 投资者数据数组

    // Creator data tracking / 创作者数据追踪
    mapping(address => uint256) public creatorTotalPublished; // Creator => Total published count / 创作者 => 总发布数量
    mapping(address => uint256) public creatorTotalAcquired; // Creator => Total acquired count / 创作者 => 总获得数量
    mapping(address => mapping(uint256 => uint256)) public creatorMonthlyPublished; // Creator => YearMonth => Monthly published count / 创作者 => 年月 => 当月发布数量
    mapping(address => mapping(uint256 => uint256)) public creatorMonthlyAcquired; // Creator => YearMonth => Monthly acquired count / 创作者 => 年月 => 当月获得数量

    // Investor data tracking / 投资者数据追踪
    mapping(address => uint256) public investorTotalAcquired; // Investor => Total acquired count / 投资者 => 总获得数量
    mapping(address => mapping(uint256 => uint256)) public investorMonthlyAcquired; // Investor => YearMonth => Monthly acquired count / 投资者 => 年月 => 当月获得数量

    // Registered creator and investor addresses / 注册的创作者和投资者地址
    mapping(address => bool) public isCreator;
    mapping(address => bool) public isInvestor;
    address[] public creators;
    address[] public investors;

    // Token tracking mappings (moved from MangaNFT) / NFT追踪映射（从MangaNFT迁移）
    mapping(address => uint256[]) private creatorChapters;
    mapping(uint256 => address[]) private tokenOwnersList;
    mapping(uint256 => mapping(address => bool)) private tokenOwnerExists;
    mapping(address => uint256[]) private investorHeld;

    // Enhanced tracking for individual token acquisitions / 增强的单个代币获得追踪
    mapping(uint256 => mapping(address => uint256)) private tokenAcquiredByInvestor; // tokenId => investor => acquired amount
    mapping(uint256 => uint256) private totalAcquiredPerToken; // tokenId => total acquired across all investors

    // Events / 事件
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

    // Modifiers / 修饰符
    modifier onlyPlatform() {
        require(msg.sender == platformAddress, "Only platform can call");
        _;
    }

    modifier onlyEndOfMonth() {
        uint256 currentTime = block.timestamp;
        // Simplified end-of-month check: last day of every 30 days / 简化的月末检查：每30天的最后一天
        uint256 dayInMonth = (currentTime / 1 days) % 30;
        require(dayInMonth >= 28, "Can only upload near end of month");
        _;
    }

    constructor(address _platformAddress, address _mangaNFTContract) Ownable(msg.sender) {
        require(_platformAddress != address(0), "Invalid Platform Address");
        require(_mangaNFTContract != address(0), "Invalid MangaNFT Contract Address");
        platformAddress = _platformAddress;
        mangaNFTContract = IERC1155(_mangaNFTContract);
    }

    // Get current year-month (format: YYYYMM) / 获取当前年月（格式：YYYYMM）
    function getCurrentYearMonth() public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        // Simplified year-month calculation / 简化的年月计算
        uint256 year = 2024 + ((timestamp - 1704067200) / (365 days)); // Starting from January 1, 2024 / 从2024年1月1日开始
        uint256 month = (((timestamp - 1704067200) % (365 days)) / (30 days)) + 1;
        if (month > 12) month = 12;
        return year * 100 + month;
    }

    // Record creator NFT publish information / 记录创作者发布NFT信息
    function recordCreatorPublish(address creator, uint256 publishedCount, uint256 acquiredCount)
        external
        onlyPlatform
    {
        require(creator != address(0), "Invalid creator address");

        // If not a creator, register as creator first / 如果不是创作者，先注册为创作者
        if (!isCreator[creator]) {
            isCreator[creator] = true;
            creators.push(creator);
        }

        uint256 currentYearMonth = getCurrentYearMonth();

        // Update monthly published count / 更新当月发布数量
        creatorMonthlyPublished[creator][currentYearMonth] += publishedCount;

        // Update total published count / 更新总发布数量
        creatorTotalPublished[creator] += publishedCount;

        // Update monthly acquired count (platform minted to author) / 更新当月获得数量（平台mint给作者的数量）
        creatorMonthlyAcquired[creator][currentYearMonth] += acquiredCount;

        // Update total acquired count / 更新总获得数量
        creatorTotalAcquired[creator] += acquiredCount;

        emit CreatorNFTPublished(creator, publishedCount, creatorTotalPublished[creator], acquiredCount);
    }

    // Record investor NFT acquire information / 记录投资者获得NFT信息
    function recordInvestorAcquire(address investor, uint256 acquiredCount) external onlyPlatform {
        require(investor != address(0), "Invalid investor address");

        // If not an investor, register as investor first / 如果不是投资者，先注册为投资者
        if (!isInvestor[investor]) {
            isInvestor[investor] = true;
            investors.push(investor);
        }

        uint256 currentYearMonth = getCurrentYearMonth();

        // Update monthly acquired count / 更新当月获得数量
        investorMonthlyAcquired[investor][currentYearMonth] += acquiredCount;

        // Update total acquired count / 更新总获得数量
        investorTotalAcquired[investor] += acquiredCount;

        emit InvestorNFTAcquired(investor, acquiredCount, investorTotalAcquired[investor]);
    }

    // Upload monthly data (can only be executed at end of month) / 上传月度数据（只能在月末执行）
    function uploadMonthlyData() external onlyOwner onlyEndOfMonth {
        uint256 currentYearMonth = getCurrentYearMonth();

        // Upload creator data / 上传创作者数据
        _uploadCreatorData(currentYearMonth);

        // Upload investor data / 上传投资者数据
        _uploadInvestorData(currentYearMonth);

        emit MonthlyDataUploaded(currentYearMonth, creators.length, investors.length);
    }

    // Force upload monthly data (for emergency use, skip end-of-month check) / 强制上传月度数据（紧急情况下使用，跳过月末检查）
    function forceUploadMonthlyData() external onlyOwner {
        uint256 currentYearMonth = getCurrentYearMonth();

        // Upload creator data / 上传创作者数据
        _uploadCreatorData(currentYearMonth);

        // Upload investor data / 上传投资者数据
        _uploadInvestorData(currentYearMonth);

        emit MonthlyDataUploaded(currentYearMonth, creators.length, investors.length);
    }

    // Upload data for specified year-month / 指定年月上传数据
    function uploadDataForMonth(uint256 yearMonth) external onlyOwner {
        // Upload creator data / 上传创作者数据
        _uploadCreatorData(yearMonth);

        // Upload investor data / 上传投资者数据
        _uploadInvestorData(yearMonth);

        emit MonthlyDataUploaded(yearMonth, creators.length, investors.length);
    }

    // Internal function: Upload creator data / 内部函数：上传创作者数据
    function _uploadCreatorData(uint256 yearMonth) internal {
        for (uint256 i = 0; i < creators.length; i++) {
            address creator = creators[i];

            // Get monthly published count / 获取当月发布数量
            uint256 monthlyPublished = creatorMonthlyPublished[creator][yearMonth];

            // Get total published count / 获取总发布数量
            uint256 totalPublished = creatorTotalPublished[creator];

            // Get monthly acquired count / 获取当月获得数量
            uint256 monthlyAcquired = creatorMonthlyAcquired[creator][yearMonth];

            // Get creator's current held NFT total count / 获取创作者当前持有的NFT总数
            uint256 currentHeld = getCurrentHeldNFTCountByCreator(creator);

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

    // Internal function: Upload investor data / 内部函数：上传投资者数据
    function _uploadInvestorData(uint256 yearMonth) internal {
        for (uint256 i = 0; i < investors.length; i++) {
            address investor = investors[i];

            // Get monthly acquired count / 获取当月获得数量
            uint256 monthlyAcquired = investorMonthlyAcquired[investor][yearMonth];

            // Get total acquired count / 获取总获得数量
            uint256 totalAcquired = investorTotalAcquired[investor];

            // Get investor's current held NFT total count / 获取投资者当前持有的NFT总数
            uint256 currentHeld = getCurrentHeldNFTCountByInvestor(investor);

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

    // Manually add creator address / 手动添加创作者地址
    function addCreator(address creator) external onlyOwner {
        require(creator != address(0), "Invalid creator address");
        if (!isCreator[creator]) {
            isCreator[creator] = true;
            creators.push(creator);
        }
    }

    // Manually add investor address / 手动添加投资者地址
    function addInvestor(address investor) external onlyOwner {
        require(investor != address(0), "Invalid investor address");
        if (!isInvestor[investor]) {
            isInvestor[investor] = true;
            investors.push(investor);
        }
    }

    // Batch add creators / 批量添加创作者
    function addCreators(address[] calldata _creators) external onlyOwner {
        for (uint256 i = 0; i < _creators.length; i++) {
            if (_creators[i] != address(0) && !isCreator[_creators[i]]) {
                isCreator[_creators[i]] = true;
                creators.push(_creators[i]);
            }
        }
    }

    // Batch add investors / 批量添加投资者
    function addInvestors(address[] calldata _investors) external onlyOwner {
        for (uint256 i = 0; i < _investors.length; i++) {
            if (_investors[i] != address(0) && !isInvestor[_investors[i]]) {
                isInvestor[_investors[i]] = true;
                investors.push(_investors[i]);
            }
        }
    }

    // Query creator data by month / 查询某月的创作者数据
    function getCreatorDataByMonth(uint256 yearMonth) external view returns (CreatorMonthlyData[] memory) {
        return monthlyCreatorData[yearMonth];
    }

    // Query investor data by month / 查询某月的投资者数据
    function getInvestorDataByMonth(uint256 yearMonth) external view returns (InvestorMonthlyData[] memory) {
        return monthlyInvestorData[yearMonth];
    }

    // Query specific creator's monthly data / 查询特定创作者某月的数据
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

    // Query specific investor's monthly data / 查询特定投资者某月的数据
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

    // Get all registered creators / 获取所有注册的创作者
    function getAllCreators() external view returns (address[] memory) {
        return creators;
    }

    // Get all registered investors / 获取所有注册的投资者
    function getAllInvestors() external view returns (address[] memory) {
        return investors;
    }

    // Get creator statistics / 获取创作者的统计信息
    function getCreatorStats(address creator)
        external
        view
        returns (uint256 totalPublished, uint256 totalAcquired, uint256 currentHeld)
    {
        totalPublished = creatorTotalPublished[creator];
        totalAcquired = creatorTotalAcquired[creator];
        currentHeld = getCurrentHeldNFTCountByCreator(creator);
    }

    // Get investor statistics / 获取投资者的统计信息
    function getInvestorStats(address investor) external view returns (uint256 totalAcquired, uint256 currentHeld) {
        totalAcquired = investorTotalAcquired[investor];
        currentHeld = getCurrentHeldNFTCountByInvestor(investor);
    }

    // Get creator's monthly publish and acquire count / 获取创作者某月的发布和获得数量
    function getCreatorMonthlyStats(address creator, uint256 yearMonth)
        external
        view
        returns (uint256 monthlyPublished, uint256 monthlyAcquired)
    {
        monthlyPublished = creatorMonthlyPublished[creator][yearMonth];
        monthlyAcquired = creatorMonthlyAcquired[creator][yearMonth];
    }

    // Get investor's monthly acquire count / 获取投资者某月的获得数量
    function getInvestorMonthlyStats(address investor, uint256 yearMonth)
        external
        view
        returns (uint256 monthlyAcquired)
    {
        monthlyAcquired = investorMonthlyAcquired[investor][yearMonth];
    }

    // Batch get creator data for multiple months / 批量获取多个月的创作者数据
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

    // Batch get investor data for multiple months / 批量获取多个月的投资者数据
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

    // Update platform address / 更新平台地址
    function updatePlatformAddress(address newPlatformAddress) external onlyOwner {
        require(newPlatformAddress != address(0), "Invalid platform address");
        platformAddress = newPlatformAddress;
    }

    // Clear monthly data (for emergency use) / 清除某月的数据（紧急情况使用）
    function clearMonthlyData(uint256 yearMonth) external onlyOwner {
        delete monthlyCreatorData[yearMonth];
        delete monthlyInvestorData[yearMonth];
    }

    // Remove creator / 移除创作者
    function removeCreator(address creator) external onlyOwner {
        require(isCreator[creator], "Address is not a creator");
        isCreator[creator] = false;

        // Remove from array / 从数组中移除
        for (uint256 i = 0; i < creators.length; i++) {
            if (creators[i] == creator) {
                creators[i] = creators[creators.length - 1];
                creators.pop();
                break;
            }
        }
    }

    // Remove investor / 移除投资者
    function removeInvestor(address investor) external onlyOwner {
        require(isInvestor[investor], "Address is not an investor");
        isInvestor[investor] = false;

        // Remove from array / 从数组中移除
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == investor) {
                investors[i] = investors[investors.length - 1];
                investors.pop();
                break;
            }
        }
    }

    // ========== Token Tracking Functions (moved from MangaNFT) / NFT追踪函数（从MangaNFT迁移） ==========

    // Update ownership tracking / 更新所有权追踪
    function updateOwnership(uint256 tokenId, address owner) external {
        require(msg.sender == address(mangaNFTContract), "Only MangaNFT can call");
        if (!tokenOwnerExists[tokenId][owner]) {
            tokenOwnerExists[tokenId][owner] = true;
            tokenOwnersList[tokenId].push(owner);
        }
    }

    // Add creator chapter / 添加创作者章节
    function addCreatorChapter(address creator, uint256 tokenId) external {
        require(msg.sender == address(mangaNFTContract), "Only MangaNFT can call");
        creatorChapters[creator].push(tokenId);
    }

    // Add investor held token / 添加投资者持有的代币
    function addInvestorHeld(address investor, uint256 tokenId) external {
        require(msg.sender == address(mangaNFTContract), "Only MangaNFT can call");
        investorHeld[investor].push(tokenId);
    }

    // Get token owners / 获取代币所有者
    function getTokenOwners(uint256 tokenId) external view returns (address[] memory) {
        return tokenOwnersList[tokenId];
    }

    // Enhanced: Get current held NFT count by creator / 增强：获取创作者当前持有的NFT数量
    function getCurrentHeldNFTCountByCreator(address creator) internal view returns (uint256 total) {
        // Method 1: Check all tracked chapters for this creator / 方法1：检查此创作者的所有追踪章节
        uint256[] memory chapters = creatorChapters[creator];
        for (uint256 i = 0; i < chapters.length; i++) {
            uint256 tokenId = chapters[i];
            uint256 balance = mangaNFTContract.balanceOf(creator, tokenId);
            if (balance > 0) {
                total += balance;
            }
        }

        return total;
    }

    // Enhanced: Get current held NFT count by investor / 增强：获取投资者当前持有的NFT数量
    function getCurrentHeldNFTCountByInvestor(address investor) internal view returns (uint256 total) {
        // Method 1: Check all tracked tokens for this investor / 方法1：检查此投资者的所有追踪代币
        uint256[] memory chapters = investorHeld[investor];
        for (uint256 i = 0; i < chapters.length; i++) {
            uint256 tokenId = chapters[i];
            uint256 balance = mangaNFTContract.balanceOf(investor, tokenId);
            if (balance > 0) {
                total += balance;
            }
        }

        return total;
    }

    // Get NFT owners with balance / 获取NFT所有者及其余额
    function getNFTOwnersWithBalance(uint256 tokenId) external view returns (NFTOwner[] memory) {
        address[] memory owners = tokenOwnersList[tokenId];
        NFTOwner[] memory results = new NFTOwner[](owners.length);

        for (uint256 i = 0; i < owners.length; i++) {
            results[i] = NFTOwner({owner: owners[i], balance: mangaNFTContract.balanceOf(owners[i], tokenId)});
        }

        return results;
    }

    // External wrapper functions for MangaNFT to call / MangaNFT调用的外部包装函数
    function getCurrentHeldNFTCountByCreatorExternal(address creator) external view returns (uint256) {
        return getCurrentHeldNFTCountByCreator(creator);
    }

    function getCurrentHeldNFTCountByInvestorExternal(address investor) external view returns (uint256) {
        return getCurrentHeldNFTCountByInvestor(investor);
    }

    // Update mangaNFT contract address / 更新MangaNFT合约地址
    function updateMangaNFTContract(address newMangaNFTContract) external onlyOwner {
        require(newMangaNFTContract != address(0), "Invalid MangaNFT contract address");
        mangaNFTContract = IERC1155(newMangaNFTContract);
    }
}
