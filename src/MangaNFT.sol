// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// NFT Owner structure / NFT所有者结构
struct NFTOwner {
    address owner;
    uint256 balance;
}

// Monthly Data Uploader interface / 月度数据上传器接口
interface IMonthlyDataUploader {
    function recordCreatorPublish(address creator, uint256 publishedCount, uint256 acquiredCount) external;
    function recordInvestorAcquire(address investor, uint256 acquiredCount) external;
    function updateOwnership(uint256 tokenId, address owner) external;
    function addCreatorChapter(address creator, uint256 tokenId) external;
    function addInvestorHeld(address investor, uint256 tokenId) external;
    function getTokenOwners(uint256 tokenId) external view returns (address[] memory);
    function getCurrentHeldNFTCountByCreatorExternal(address creator) external view returns (uint256);
    function getCurrentHeldNFTCountByInvestorExternal(address investor) external view returns (uint256);
    function getNFTOwnersWithBalance(uint256 tokenId) external view returns (NFTOwner[] memory);
}

contract MangaNFT is ERC1155, ERC1155Supply, Ownable {
    uint256 private _tokenIdCounter;
    uint256 private _lastTimestamp;
    uint256 private _perSecondCounter;

    address public platformAddress;
    IERC20 public paymentToken;
    uint256 public mintTimeout = 5 minutes;
    IMonthlyDataUploader public monthlyDataUploader;

    // Localized text structure / 本地化文本结构
    struct LocalizedText {
        string zh;
        string en;
        string jp;
    }

    // Manga chapter structure / 漫画章节结构
    struct MangaChapter {
        LocalizedText mangaTitle;
        LocalizedText description;
        uint256 publishTime;
        uint256 mintTime;
        uint256 maxCopies;
        address creator;
        string uri;
    }

    // Pending payment structure / 待支付结构
    struct PendingPayment {
        uint256 tokenId;
        uint256 timestamp;
        uint256 amount;
        bool minted;
    }

    // Mint request structure / 铸造请求结构
    struct MintRequest {
        address recipient;
        uint256 tokenId;
        uint256 amountMinted;
    }

    // Mint success structure / 铸造成功结构
    struct MintSuccess {
        address recipient;
        uint256 tokenId;
    }

    // Mint failure structure / 铸造失败结构
    struct MintFailure {
        address recipient;
        uint256 tokenId;
        string reason;
    }

    // Storage mappings / 存储映射
    mapping(uint256 => MangaChapter) public mangaChapters;
    mapping(address => PendingPayment[]) public payments;

    // Events / 事件
    event ChapterCreated(
        uint256 indexed tokenId, address indexed creator, string mangaTitleZh, string mangaTitleEn, string mangaTitleJp
    );

    event PaymentReceived(address indexed buyer, uint256 indexed tokenId, uint256 amount);
    event ChapterMinted(uint256 indexed tokenId, address indexed to, uint256 amountMinted, uint256 mintTime);
    event RefundIssued(address indexed buyer, uint256 indexed tokenId, uint256 amount);
    event BatchMinted(address[] recipients, uint256[] tokenIds);

    event MangaTitleUpdated(uint256 indexed tokenId, string language, string newTitle);
    event ChapterDescriptionUpdated(uint256 indexed tokenId, string language, string newDescription);
    event ChapterDescriptionUpdated(uint256 indexed tokenId, string newDescription);
    event PlatformAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event PaymentTokenUpdated(address indexed oldToken, address indexed newToken);

    event BatchFreeMinted(MintSuccess[] successes, MintFailure[] failures);

    // Modifiers / 修饰符
    modifier onlyPlatform() {
        require(msg.sender == platformAddress, "Only platform can mint");
        _;
    }

    constructor(string memory _uri, address _platformAddress, address _paymentToken, address _monthlyDataUploader)
        ERC1155(_uri)
        Ownable(msg.sender)
    {
        require(_platformAddress != address(0), "Invalid platform address");
        require(_paymentToken != address(0), "Invalid token address");
        require(_monthlyDataUploader != address(0), "Invalid monthly data uploader address");
        platformAddress = _platformAddress;
        paymentToken = IERC20(_paymentToken);
        monthlyDataUploader = IMonthlyDataUploader(_monthlyDataUploader);

        // Update the MangaNFT contract address in MonthlyDataUploader / 更新MonthlyDataUploader中的MangaNFT合约地址
        // Note: This requires the MonthlyDataUploader to be deployed first / 注意：这需要先部署MonthlyDataUploader
        // and the deployer to have owner permissions / 并且部署者需要拥有所有者权限
    }

    // Generate unique token ID / 生成唯一代币ID
    function generateTokenId() internal returns (uint256) {
        uint256 currentTimestamp = block.timestamp;

        if (currentTimestamp != _lastTimestamp) {
            _lastTimestamp = currentTimestamp;
            _perSecondCounter = 0;
        }

        _perSecondCounter++;

        uint256 tokenId = currentTimestamp * 1e6 + _perSecondCounter;

        return tokenId;
    }

    // Token tracking functions now call MonthlyDataUploader / 代币追踪函数现在调用MonthlyDataUploader
    function getTokenOwners(uint256 tokenId) external view returns (address[] memory) {
        return monthlyDataUploader.getTokenOwners(tokenId);
    }

    function getCurrentHeldNFTCountByCreator(address creator) external view returns (uint256) {
        return monthlyDataUploader.getCurrentHeldNFTCountByCreatorExternal(creator);
    }

    function getCurrentHeldNFTCountByInvestor(address investor) external view returns (uint256) {
        return monthlyDataUploader.getCurrentHeldNFTCountByInvestorExternal(investor);
    }

    function getNFTOwnersWithBalance(uint256 tokenId) external view returns (NFTOwner[] memory) {
        return monthlyDataUploader.getNFTOwnersWithBalance(tokenId);
    }

    // Create new manga chapter / 创建新的漫画章节
    function createChapter(
        string memory mangaTitleZh,
        string memory mangaTitleEn,
        string memory mangaTitleJp,
        string memory descriptionZh,
        string memory descriptionEn,
        string memory descriptionJp,
        uint256 maxCopies,
        string memory uri_,
        address creator_addr
    ) external returns (uint256) {
        uint256 newTokenId = generateTokenId();

        require(maxCopies > 0 && maxCopies % 10 == 0, "maxCopies must be multiple of 10");

        LocalizedText memory title = LocalizedText({zh: mangaTitleZh, en: mangaTitleEn, jp: mangaTitleJp});

        LocalizedText memory desc = LocalizedText({zh: descriptionZh, en: descriptionEn, jp: descriptionJp});

        mangaChapters[newTokenId] = MangaChapter({
            mangaTitle: title,
            description: desc,
            publishTime: block.timestamp,
            mintTime: 0,
            maxCopies: maxCopies,
            creator: creator_addr,
            uri: uri_
        });

        emit ChapterCreated(newTokenId, creator_addr, mangaTitleZh, mangaTitleEn, mangaTitleJp);

        // Add creator chapter to tracking / 添加创作者章节到追踪
        monthlyDataUploader.addCreatorChapter(creator_addr, newTokenId);

        uint256 amountToMint = (maxCopies * 4) / 5;
        _mint(creator_addr, newTokenId, amountToMint, "");
        _mint(platformAddress, newTokenId, 1, "");

        // Update ownership tracking / 更新所有权追踪
        monthlyDataUploader.updateOwnership(newTokenId, creator_addr);
        mangaChapters[newTokenId].mintTime = block.timestamp;

        // Record creator publish data / 记录创作者发布数据
        monthlyDataUploader.recordCreatorPublish(creator_addr, maxCopies, amountToMint);

        emit ChapterMinted(newTokenId, creator_addr, amountToMint, block.timestamp);

        return newTokenId;
    }

    // Free mint function / 免费铸造函数
    function freeMint(address to, uint256 tokenId, uint256 amountMinted) public onlyPlatform {
        require(to != address(0), "Invalid recipient");

        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) + amountMinted <= chapter.maxCopies, "No more copies");

        chapter.mintTime = block.timestamp;
        _mint(to, tokenId, amountMinted, "");

        // Update ownership tracking / 更新所有权追踪
        monthlyDataUploader.updateOwnership(tokenId, to);
        monthlyDataUploader.addInvestorHeld(to, tokenId);

        // Record investor acquire data / 记录投资者获得数据
        monthlyDataUploader.recordInvestorAcquire(to, amountMinted);

        emit ChapterMinted(tokenId, to, amountMinted, block.timestamp);
    }

    // Investor registration function / 投资者注册函数
    function investorRegistration(address investor, uint256 tokenId) public onlyPlatform {
        require(investor != address(0), "Invalid address");
        require(balanceOf(investor, tokenId) > 0, "Investor does not hold this NFT");
        monthlyDataUploader.updateOwnership(tokenId, investor);
        monthlyDataUploader.addInvestorHeld(investor, tokenId);
    }

    // Get chapter title by language / 根据语言获取章节标题
    function getChapterTitle(uint256 tokenId, string memory lang) external view returns (string memory) {
        LocalizedText memory title = mangaChapters[tokenId].mangaTitle;
        if (keccak256(bytes(lang)) == keccak256("zh")) return title.zh;
        if (keccak256(bytes(lang)) == keccak256("en")) return title.en;
        if (keccak256(bytes(lang)) == keccak256("jp")) return title.jp;
        return "";
    }

    // Update manga title / 更新漫画标题
    function updateMangaTitle(uint256 tokenId, string memory language, string memory newTitle) external {
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(msg.sender == chapter.creator, "Only creator can update");

        if (keccak256(bytes(language)) == keccak256(bytes("zh"))) {
            chapter.mangaTitle.zh = newTitle;
        } else if (keccak256(bytes(language)) == keccak256(bytes("en"))) {
            chapter.mangaTitle.en = newTitle;
        } else if (keccak256(bytes(language)) == keccak256(bytes("jp"))) {
            chapter.mangaTitle.jp = newTitle;
        } else {
            revert("Unsupported language");
        }

        emit MangaTitleUpdated(tokenId, language, newTitle);
    }

    // Update chapter description / 更新章节描述
    function updateChapterDescription(uint256 tokenId, string memory language, string memory newDescription) external {
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(msg.sender == chapter.creator, "Only creator can update");

        if (keccak256(bytes(language)) == keccak256(bytes("zh"))) {
            chapter.description.zh = newDescription;
        } else if (keccak256(bytes(language)) == keccak256(bytes("en"))) {
            chapter.description.en = newDescription;
        } else if (keccak256(bytes(language)) == keccak256(bytes("jp"))) {
            chapter.description.jp = newDescription;
        } else {
            revert("Unsupported language");
        }

        emit ChapterDescriptionUpdated(tokenId, language, newDescription);
    }

    // Safe free mint function / 安全的免费铸造函数
    function _safeFreeMint(address to, uint256 tokenId, uint256 amountMinted) external onlyPlatform {
        require(to != address(0), "Invalid address");

        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) + amountMinted <= chapter.maxCopies, "Max supply reached");
        _mint(to, tokenId, amountMinted, "");
        chapter.mintTime = block.timestamp;
    }

    // Batch safe free mint function / 批量安全免费铸造函数
    function batchSafeFreeMint(MintRequest[] calldata requests) external onlyPlatform {
        MintSuccess[] memory successes = new MintSuccess[](requests.length);
        MintFailure[] memory failures = new MintFailure[](requests.length);

        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint256 i = 0; i < requests.length; i++) {
            MintRequest calldata req = requests[i];
            try this._safeFreeMint(req.recipient, req.tokenId, req.amountMinted) {
                successes[successCount] = MintSuccess(req.recipient, req.tokenId);
                successCount++;

                monthlyDataUploader.updateOwnership(req.tokenId, req.recipient);
                monthlyDataUploader.addInvestorHeld(req.recipient, req.tokenId);

                // Record investor acquire data / 记录投资者获得数据
                monthlyDataUploader.recordInvestorAcquire(req.recipient, req.amountMinted);
            } catch Error(string memory reason) {
                failures[failCount] = MintFailure(req.recipient, req.tokenId, reason);
                failCount++;
            } catch {
                failures[failCount] = MintFailure(req.recipient, req.tokenId, "Unknown error");
                failCount++;
            }
        }

        assembly {
            mstore(successes, successCount)
            mstore(failures, failCount)
        }

        emit BatchFreeMinted(successes, failures);
    }

    // Update function override / 更新函数重写
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    // Get chapter information / 获取章节信息
    function getChapterInfo(uint256 tokenId) external view returns (MangaChapter memory) {
        return mangaChapters[tokenId];
    }

    // Get URI for token / 获取代币的URI
    function uri(uint256 tokenId) public view override returns (string memory) {
        return mangaChapters[tokenId].uri;
    }

    // Update platform address / 更新平台地址
    function updatePlatformAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Invalid address");
        address oldAddress = platformAddress;
        platformAddress = newAddress;
        emit PlatformAddressUpdated(oldAddress, newAddress);
    }

    // Update payment token / 更新支付代币
    function updatePaymentToken(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        address oldToken = address(paymentToken);
        paymentToken = IERC20(newToken);
        emit PaymentTokenUpdated(oldToken, newToken);
    }

    // Update monthly data uploader / 更新月度数据上传器
    function updateMonthlyDataUploader(address newMonthlyDataUploader) external onlyOwner {
        require(newMonthlyDataUploader != address(0), "Invalid monthly data uploader address");
        monthlyDataUploader = IMonthlyDataUploader(newMonthlyDataUploader);
    }
}
