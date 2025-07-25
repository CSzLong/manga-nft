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
    
    mapping(uint256 => mapping(address => uint256)) public mintedPerUser;

    /*
    struct MangaChapter {
        string mangaTitle;
        string chapterTitle;
        string description;
        string language;
        uint256 seriesId;
        uint256 chapterNumber;
        uint256 publishTime;
        uint256 mintTime;
        uint256 maxPerUser; 
        address creator;
        string uri;
        string copyright;
        uint256 price;
        bool isFinal;
    }*/
    
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
        //uint256 maxPerUser;
        address creator;
        string uri;
    }

    struct PendingPayment {
        uint256 tokenId;
        uint256 timestamp;
        uint256 amount;
        bool minted;
    }

    mapping(uint256 => MangaChapter) public mangaChapters;
    mapping(address => PendingPayment[]) public payments;
    
    //event ChapterCreated(uint256 indexed tokenId, address indexed creator, string mangaTitle);
    event ChapterCreated(
        uint256 indexed tokenId,
        address indexed creator,
        string mangaTitleZh,
        string mangaTitleEn,
        string mangaTitleJp
    );
        
    event PaymentReceived(address indexed buyer, uint256 indexed tokenId, uint256 amount);
    event ChapterMinted(uint256 indexed tokenId, address indexed to, uint256 mintTime);
    event RefundIssued(address indexed buyer, uint256 indexed tokenId, uint256 amount);
    event BatchMinted(address[] recipients, uint256[] tokenIds);
    //event ChapterFinalFlagUpdated(uint256 indexed tokenId, bool isFinal);
    //event ChapterPriceUpdated(uint256 indexed tokenId, uint256 newPrice);
    //event ChapterTitleUpdated(uint256 indexed tokenId, string newTitle);
    //event MangaTitleUpdated(uint256 indexed tokenId, string newTitle);
    event MangaTitleUpdated(uint256 indexed tokenId, string language, string newTitle);
    event ChapterDescriptionUpdated(uint256 indexed tokenId, string language, string newDescription);
    event ChapterDescriptionUpdated(uint256 indexed tokenId, string newDescription);
    event PlatformAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event PaymentTokenUpdated(address indexed oldToken, address indexed newToken);

    event BatchFreeMinted(
    address[] successfulRecipients,
    uint256[] successfulTokenIds,
    address[] failedRecipients,
    uint256[] failedTokenIds,
    string[] reasons
    );
    
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
        
        // 拼接 tokenId: timestamp * 1e6 + counter (最多6位)
        uint256 tokenId = currentTimestamp * 1e6 + _perSecondCounter;
        
        return tokenId;
    }

    function createChapter(
        string memory mangaTitleZh,
        string memory mangaTitleEn,
        string memory mangaTitleJp,
        string memory descriptionZh,
        string memory descriptionEn,
        string memory descriptionJp,
        uint256 maxCopies,
        string memory uri_
    ) external returns (uint256) {
        uint256 newTokenId = generateTokenId();

        require(maxCopies > 0 && maxCopies % 5 == 0, "maxCopies must be multiple of 5");

        LocalizedText memory title = LocalizedText({
            zh: mangaTitleZh,
            en: mangaTitleEn,
            jp: mangaTitleJp
        });

        LocalizedText memory desc = LocalizedText({
            zh: descriptionZh,
            en: descriptionEn,
            jp: descriptionJp
        });
        
        mangaChapters[newTokenId] = MangaChapter({
            mangaTitle: title,
            description: desc,
            publishTime: block.timestamp,
            mintTime:0,
            maxCopies: maxCopies,
            creator: msg.sender,
            uri: uri_
        });

        //emit ChapterCreated(newTokenId, msg.sender, mangaTitle);
        emit ChapterCreated(
            newTokenId,
            msg.sender,
            mangaTitleZh,
            mangaTitleEn,
            mangaTitleJp
        );
                

        uint256 amountToMint = (maxCopies * 4) / 5;
        _mint(msg.sender, newTokenId, amountToMint, "");
        mintedPerUser[newTokenId][msg.sender] = amountToMint;
        mangaChapters[newTokenId].mintTime = block.timestamp;

        emit ChapterMinted(newTokenId, msg.sender, block.timestamp);
            
        return newTokenId;
    }

    function freeMint(address to, uint256 tokenId) public onlyPlatform {
        require(to != address(0), "Invalid recipient");
        
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) < chapter.maxCopies, "No more copies");
        
        /*require(
            mintedPerUser[tokenId][to] < chapter.maxPerUser,
            "Mint limit per user reached"
        );*/
        
        chapter.mintTime = block.timestamp;
        _mint(to, tokenId, 1, "");
        
        mintedPerUser[tokenId][to] += 1; 

        emit ChapterMinted(tokenId, to, block.timestamp);
    }
    
    
    function getChapterTitle(uint256 tokenId, string memory lang) external view returns (string memory) {
        LocalizedText memory title = mangaChapters[tokenId].mangaTitle;
        if (keccak256(bytes(lang)) == keccak256("zh")) return title.zh;
        if (keccak256(bytes(lang)) == keccak256("en")) return title.en;
        if (keccak256(bytes(lang)) == keccak256("jp")) return title.jp;
        return "";
    }
    
    function updateMangaTitle(
        uint256 tokenId,
        string memory language,
        string memory newTitle
    ) external {
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

    function updateChapterDescription(
        uint256 tokenId,
        string memory language,
        string memory newDescription
    ) external {
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
        

    /*
    function createChapter(
        string memory mangaTitle,
        string memory chapterTitle,
        string memory description,
        string memory language,
        uint256 seriesId,
        uint256 chapterNumber,
        uint256 publishTime,
        uint256 maxCopies,
        uint256 maxPerUser,
        string memory uri_,
        string memory copyright,
        uint256 price,
        bool isFinal
    ) external returns (uint256) {
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        mangaChapters[newTokenId] = MangaChapter({
            mangaTitle: mangaTitle,
            chapterTitle: chapterTitle,
            description: description,
            language: language,
            seriesId: seriesId,
            chapterNumber: chapterNumber,
            publishTime: publishTime,
            mintTime: 0,
            maxCopies: maxCopies,
            maxPerUser: maxPerUser,
            creator: msg.sender,
            uri: uri_,
            copyright: copyright,
            price: price,
            isFinal: isFinal
        });

        emit ChapterCreated(newTokenId, msg.sender, mangaTitle);
        return newTokenId;
    }
   
    function mintChapter(address to, uint256 tokenId, uint256 amountMinted) public onlyPlatform {
        require(to != address(0), "Invalid recipient");

        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) + amountMinted <= chapter.maxCopies, "No more copies");
        bool found = false;
        PendingPayment[] storage userPayments = payments[to];

        for (uint i = 0; i < userPayments.length; i++) {
            if (
                userPayments[i].tokenId == tokenId &&
                !userPayments[i].minted &&
                block.timestamp <= userPayments[i].timestamp + mintTimeout
            ) {
                userPayments[i].minted = true;
                found = true;
                break;
            }
        }
        
        require(found, "No valid payment found");
        
        chapter.mintTime = block.timestamp;
        _mint(to, tokenId, amountMinted, "");
        
        emit ChapterMinted(tokenId, to, amountMinted, block.timestamp);
    }
    
    function getCurrentHeldNFTCountByCreator(address creator) external view returns (uint256 total) {
        uint256[] memory chapters = creatorChapters[creator];
        for (uint256 i = 0; i < chapters.length; i++) {
            uint256 tokenId = chapters[i];
            total += balanceOf(creator, tokenId); 
        }
        return total; 
    }
        
    
    function refundIfExpired(address buyer, uint256 tokenId) external {
        PendingPayment[] storage userPayments = payments[buyer];
        for (uint i = 0; i < userPayments.length; i++) {
            PendingPayment storage p = userPayments[i];
            if (
                p.tokenId == tokenId &&
                !p.minted &&
                block.timestamp > p.timestamp + mintTimeout
            ) {
                uint256 refundAmount = p.amount;
                p.amount = 0;
                p.minted = true;

                require(paymentToken.transfer(buyer, refundAmount), "Refund failed");
                emit RefundIssued(buyer, tokenId, refundAmount);
                break;
            }
        }
    }
    
    function batchMintChapter(address[] calldata recipients, uint256[] calldata tokenIds, uint256[] calldata amountMinteds) external onlyPlatform {
        require(recipients.length == tokenIds.length, "Array length mismatch");
        for (uint i = 0; i < recipients.length; i++) {
            mintChapter(recipients[i], tokenIds[i], amountMinteds[i]);
        }
        emit BatchMinted(recipients, tokenIds);
    }
    
    
    function payForChapter(uint256 tokenId) external {
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(chapter.price > 0, "Chapter is not for sale");
        
        require(paymentToken.transferFrom(msg.sender, platformAddress, chapter.price), "Payment failed");

        payments[msg.sender].push(PendingPayment({
            tokenId: tokenId,
            timestamp: block.timestamp,
            amount: chapter.price,
            minted: false
        }));

        emit PaymentReceived(msg.sender, tokenId, chapter.price);
    }
     */
    function mintChapter(address to, uint256 tokenId) public onlyPlatform {
        require(to != address(0), "Invalid recipient");

        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) < chapter.maxCopies, "No more copies");
        /*
        require(
            mintedPerUser[tokenId][to] < chapter.maxPerUser,
            "Mint limit per user reached"
        );*/
        
        bool found = false;
        PendingPayment[] storage userPayments = payments[to];

        for (uint i = 0; i < userPayments.length; i++) {
            if (
                userPayments[i].tokenId == tokenId &&
                !userPayments[i].minted &&
                block.timestamp <= userPayments[i].timestamp + mintTimeout
            ) {
                userPayments[i].minted = true;
                found = true;
                break;
            }
        }

        require(found, "No valid payment found");

        chapter.mintTime = block.timestamp;
        _mint(to, tokenId, 1, "");

        emit ChapterMinted(tokenId, to, block.timestamp);
    }
    
    function refundIfExpired(address buyer, uint256 tokenId) external {
        PendingPayment[] storage userPayments = payments[buyer];
        for (uint i = 0; i < userPayments.length; i++) {
            PendingPayment storage p = userPayments[i];
            if (
                p.tokenId == tokenId &&
                !p.minted &&
                block.timestamp > p.timestamp + mintTimeout
            ) {
                uint256 refundAmount = p.amount;
                p.amount = 0;
                p.minted = true;

                require(paymentToken.transfer(buyer, refundAmount), "Refund failed");
                emit RefundIssued(buyer, tokenId, refundAmount);
                break;
            }
        }
    }

    function batchMintChapter(address[] calldata recipients, uint256[] calldata tokenIds) external onlyPlatform {
        require(recipients.length == tokenIds.length, "Array length mismatch");
        for (uint i = 0; i < recipients.length; i++) {
            mintChapter(recipients[i], tokenIds[i]);
        }
        emit BatchMinted(recipients, tokenIds);
    }
    
    
    function _safeFreeMint(address to, uint256 tokenId) external onlyPlatform {
        require(to != address(0), "Invalid address");
        
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(totalSupply(tokenId) < chapter.maxCopies, "Max supply reached");
        
        // require(mintedPerUser[tokenId][to] < chapter.maxPerUser, "User mint limit exceeded");

        _mint(to, tokenId, 1, "");
        
        chapter.mintTime = block.timestamp;
        mintedPerUser[tokenId][to]++;

        emit ChapterMinted(tokenId, to, block.timestamp);
    }
        

    function batchFreeMint(address[] calldata recipients, uint256[] calldata tokenIds) external onlyPlatform {
        require(recipients.length == tokenIds.length, "Array length mismatch");

        address[] memory successfulRecipients = new address[](recipients.length);
        uint256[] memory successfulTokenIds = new uint256[](tokenIds.length);
        address[] memory failedRecipients = new address[](recipients.length);
        uint256[] memory failedTokenIds = new uint256[](tokenIds.length);
        string[] memory reasons = new string[](recipients.length);

        uint successCount = 0;
        uint failCount = 0;

        for (uint i = 0; i < recipients.length; i++) {
            try this._safeFreeMint(recipients[i], tokenIds[i]) {
                successfulRecipients[successCount] = recipients[i];
                successfulTokenIds[successCount] = tokenIds[i];
                successCount++;
            } catch Error(string memory reason) {
                failedRecipients[failCount] = recipients[i];
                failedTokenIds[failCount] = tokenIds[i];
                reasons[failCount] = reason;
                failCount++;
            } catch {
                failedRecipients[failCount] = recipients[i];
                failedTokenIds[failCount] = tokenIds[i];
                reasons[failCount] = "Unknown error";
                failCount++;
            }
        }
        
        assembly {
            mstore(successfulRecipients, successCount)
            mstore(successfulTokenIds, successCount)
            mstore(failedRecipients, failCount)
            mstore(failedTokenIds, failCount)
            mstore(reasons, failCount)
        }

        emit BatchFreeMinted(
            successfulRecipients,
            successfulTokenIds,
            failedRecipients,
            failedTokenIds,
            reasons
        );
    }
    
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override(ERC1155, ERC1155Supply) {
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
    
    /*
    
    function updateIsFinal(uint256 tokenId, bool newIsFinal) external {
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(msg.sender== chapter.creator, "Only creator can update");
        chapter.isFinal = newIsFinal;
        emit ChapterFinalFlagUpdated(tokenId, newIsFinal);
    }

    function updatePrice(uint256 tokenId, uint256 newPrice) external {
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(msg.sender == chapter.creator, "Only creator can update");
        chapter.price = newPrice;
        emit ChapterPriceUpdated(tokenId, newPrice);
    }

    function updateChapterTitle(uint256 tokenId, string memory newTitle) external {
        MangaChapter storage chapter = mangaChapters[tokenId];
        require(msg.sender == chapter.creator, "Only creator can update");
        chapter.chapterTitle = newTitle;
        emit ChapterTitleUpdated(tokenId, newTitle);
    }
    */
}