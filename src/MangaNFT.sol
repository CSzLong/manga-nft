// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MangaNFT is ERC1155, ERC1155Supply, Ownable {
    uint256 private _tokenIdCounter;
    uint256 private _lastTimestamp;
    uint256 private _perSecondCounter;

    address public platformAddress;
    IERC20 public paymentToken;
    uint256 public mintTimeout = 5 minutes;

    struct LocalizedText {
        string zh;
        string en;
        string jp;
    }

    struct MangaChapter {
        LocalizedText mangaTitle;
        LocalizedText description;
        uint256 publishTime;
        uint256 mintTime;
        uint256 maxCopies;
        address creator;
        string uri;
    }

    struct PendingPayment {
        uint256 tokenId;
        uint256 timestamp;
        uint256 amount;
        bool minted;
    }

    struct NFTOwner {
        address owner;
        uint256 balance;
    }

    struct MintRequest {
        address recipient;
        uint256 tokenId;
        uint256 amountMinted;
    }

    struct MintSuccess {
        address recipient;
        uint256 tokenId;
    }

    struct MintFailure {
        address recipient;
        uint256 tokenId;
        string reason;
    }

    mapping(uint256 => MangaChapter) public mangaChapters;
    mapping(address => PendingPayment[]) public payments;
    mapping(address => uint256[]) private creatorChapters;
    mapping(uint256 => address[]) private tokenOwnersList;
    mapping(uint256 => mapping(address => bool)) private tokenOwnerExists;
    mapping(address => uint256[]) private investorHeld;

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

    modifier onlyPlatform() {
        require(msg.sender == platformAddress, "Only platform can mint");
        _;
    }

    constructor(string memory _uri, address _platformAddress, address _paymentToken)
        ERC1155(_uri)
        Ownable(msg.sender)
    {
        require(_platformAddress != address(0), "Invalid platform address");
        require(_paymentToken != address(0), "Invalid token address");
        platformAddress = _platformAddress;
        paymentToken = IERC20(_paymentToken);
    }

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

    function _updateOwnership(uint256 tokenId, address owner) internal {
        if (!tokenOwnerExists[tokenId][owner]) {
            tokenOwnerExists[tokenId][owner] = true;
            tokenOwnersList[tokenId].push(owner);
        }
    }

    function getTokenOwners(uint256 tokenId) external view returns (address[] memory) {
        return tokenOwnersList[tokenId];
    }

    function getCurrentHeldNFTCountByCreator(address creator) external view returns (uint256 total) {
        uint256[] memory chapters = creatorChapters[creator];
        for (uint256 i = 0; i < chapters.length; i++) {
            uint256 tokenId = chapters[i];
            total += balanceOf(creator, tokenId);
        }
        return total;
    }

    function getCurrentHeldNFTCountByInvestor(address investor) external view returns (uint256 total) {
        uint256[] memory chapters = investorHeld[investor];
        for (uint256 i = 0; i < chapters.length; i++) {
            uint256 tokenId = chapters[i];
            total += balanceOf(investor, tokenId);
        }
        return total;
    }

    function getNFTOwnersWithBalance(uint256 tokenId) external view returns (NFTOwner[] memory) {
        address[] memory owners = tokenOwnersList[tokenId];
        NFTOwner[] memory results = new NFTOwner[](owners.length);

        for (uint256 i = 0; i < owners.length; i++) {
            results[i] = NFTOwner({owner: owners[i], balance: balanceOf(owners[i], tokenId)});
        }

        return results;
    }

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

        creatorChapters[creator_addr].push(newTokenId);

        uint256 amountToMint = (maxCopies * 4) / 5;
        _mint(creator_addr, newTokenId, amountToMint, "");
        _mint(platformAddress, newTokenId, 1, "");

        _updateOwnership(newTokenId, creator_addr);
        mangaChapters[newTokenId].mintTime = block.timestamp;

        emit ChapterMinted(newTokenId, creator_addr, amountToMint, block.timestamp);

        return newTokenId;
    }

    function freeMint(address to, uint256 tokenId, uint256 amountMinted) public onlyPlatform {
        require(to != address(0), "Invalid recipient");

        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) + amountMinted <= chapter.maxCopies, "No more copies");

        chapter.mintTime = block.timestamp;
        _mint(to, tokenId, amountMinted, "");

        _updateOwnership(tokenId, to);
        investorHeld[to].push(tokenId);

        emit ChapterMinted(tokenId, to, amountMinted, block.timestamp);
    }

    function investorRegistration(address investor, uint256 tokenId) public onlyPlatform {
        require(investor != address(0), "Invalid address");
        require(balanceOf(investor, tokenId) > 0, "Investor does not hold this NFT");
        _updateOwnership(tokenId, investor);
        investorHeld[investor].push(tokenId);
    }

    function getChapterTitle(uint256 tokenId, string memory lang) external view returns (string memory) {
        LocalizedText memory title = mangaChapters[tokenId].mangaTitle;
        if (keccak256(bytes(lang)) == keccak256("zh")) return title.zh;
        if (keccak256(bytes(lang)) == keccak256("en")) return title.en;
        if (keccak256(bytes(lang)) == keccak256("jp")) return title.jp;
        return "";
    }

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

    function _safeFreeMint(address to, uint256 tokenId, uint256 amountMinted) external onlyPlatform {
        require(to != address(0), "Invalid address");

        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) + amountMinted <= chapter.maxCopies, "Max supply reached");
        _mint(to, tokenId, amountMinted, "");
        chapter.mintTime = block.timestamp;
    }

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

                _updateOwnership(req.tokenId, req.recipient);
                investorHeld[req.recipient].push(req.tokenId);
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

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    function getChapterInfo(uint256 tokenId) external view returns (MangaChapter memory) {
        return mangaChapters[tokenId];
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return mangaChapters[tokenId].uri;
    }

    function updatePlatformAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Invalid address");
        address oldAddress = platformAddress;
        platformAddress = newAddress;
        emit PlatformAddressUpdated(oldAddress, newAddress);
    }

    function updatePaymentToken(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        address oldToken = address(paymentToken);
        paymentToken = IERC20(newToken);
        emit PaymentTokenUpdated(oldToken, newToken);
    }
}
