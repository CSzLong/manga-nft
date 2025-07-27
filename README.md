# 📘 MangaNFT 合约用户指南

## 合约地址

```text
平台地址： 0x360dC0d137ae4FF76d419Dad6961ae974Bdd3e79
数据上传合约 MonthlyDataUploader deployed at: 0x1f7f7DE7F8d9D669DF13e3EDa279CfA2f3e07b64
NFT合约 MangaNFT deployed at: 0x8053416Ce21D141F51321D2A69785b68436667cc
```

## 🔹 概览

- **合约名称**: `MangaNFT` & `MonthlyDataUploader`

- **标准**: ERC-1155，支持多语言、角色管理、章节创建、批量/单独铸造等

- **Solidity 版本**: `^0.8.24`

- **部署地址**: _部署后请替换此处_

---

## 🚀 部署指南 / Deployment Guide

### 合约依赖关系 / Contract Dependencies

两个合约之间存在循环依赖关系：
- `MangaNFT` 需要 `MonthlyDataUploader` 的地址来调用数据追踪函数
- `MonthlyDataUploader` 需要 `MangaNFT` 的地址来查询代币余额

The two contracts have circular dependencies:
- `MangaNFT` needs `MonthlyDataUploader` address to call data tracking functions
- `MonthlyDataUploader` needs `MangaNFT` address to query token balances

### 部署步骤 / Deployment Steps

#### 方法一：单次部署（推荐） / Method 1: Single Deployment (Recommended)

使用更新后的部署脚本，自动处理循环依赖：

```bash
# Deploy both contracts together / 一次性部署两个合约
forge script script/DeployMangaNFT.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

部署脚本会自动执行以下步骤：
1. 使用临时地址部署 `MonthlyDataUploader`
2. 使用 `MonthlyDataUploader` 地址部署 `MangaNFT`
3. 更新 `MonthlyDataUploader` 中的 `MangaNFT` 地址

The deployment script automatically:
1. Deploy `MonthlyDataUploader` with temporary address
2. Deploy `MangaNFT` with `MonthlyDataUploader` address
3. Update `MangaNFT` address in `MonthlyDataUploader`

#### 方法二：分步部署 / Method 2: Step-by-step Deployment

如果需要分别部署，可以按以下步骤：

```bash
# Deploy MangaNFT with MonthlyDataUploader address / 步骤2：使用MonthlyDataUploader地址部署MangaNFT
forge script script/DeployMangaNFT.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 环境变量设置 / Environment Variables

```bash
export RPC_URL="your-rpc-url"
export PRIVATE_KEY="your-private-key"
```

### 验证部署 / Verify Deployment

部署完成后，请验证以下内容：

1. 检查合约地址是否正确
2. 验证 `MonthlyDataUploader` 中的 `mangaNFTContract` 地址
3. 验证 `MangaNFT` 中的 `monthlyDataUploader` 地址
4. 测试基本功能是否正常

After deployment, verify:
1. Contract addresses are correct
2. `mangaNFTContract` address in `MonthlyDataUploader`
3. `monthlyDataUploader` address in `MangaNFT`
4. Basic functionality works correctly

---

## 🔹 系统流程总览

### 🧑‍🎨 1. 创作者发布章节（调用 `createChapter`）

```mermaid

graph TD
A["🟩 前端：填写漫画信息"] --> B["🟩 前端：调用 createChapter()"]
B --> C["🟦 合约：保存章节数据、铸造 NFT、发出事件"]
C --> D["🟩 前端：监听事件，存储 NFT 和创作者信息"]

```

---

### 🧾 2. 平台调用 `freeMint` 单独铸造流程

```mermaid

graph TD
A["🟩 前端：用户请求铸造"] --> B["🟩 前端：构造参数"]
B --> C["🟩 前端：调用 freeMint()"]
C --> D["🟦 合约：验证并调用 _mint()"]
D --> E["🟦 合约：将用户更新成投资者"]
E --> F["🟦 合约：发出 ChapterMinted 事件"]
F --> G["🟩 前端：监听事件，提示用户铸造成功"]

```

---

### 💰 3. 投资者平台交易确认与超时处理

```mermaid

graph TD
A["🟩 投资者付款"] --> B["🟩 平台：创建交易记录"]
B --> C["投资者 & 创作者线下转移 NFT"]
C --> D{"🟩 投资者是否在 3 天内点击确认？"}

D -- 是 --> E["🟩 平台：调用 investorRegistration()"]
E --> F{"合约验证是否持有 NFT？"}
F -- 是 --> G["🟦 合约更新持有人"]
G --> H["🟩 平台付款给创作者，标记成功"]
F -- 否 --> I["🟩 平台退款投资者，标记失败"]

D -- 否 --> J["🟩 平台：等待"]
J --> K["⏰ 超过 3 天后自动调用 investorRegistration()"]
K --> L{"合约验证是否持有？"}
L -- 是 --> M["🟩 更新为成功，付款创作者"]
L -- 否 --> N["🟩 退款投资者，记录失败"]

```

---

### 🔄 4. 私下交易后的注册为投资者

```mermaid

graph TD
A["🟩 私下交易完成"] --> B["🟩 前端：生成注册请求"]
B --> C["🟩 前端：调用 investorRegistration()"]
C --> D["🟦 合约：校验是否持有"]
D --> E{"校验结果？"}
E -- 成功 --> F["🟩 更新投资者数据"]
E -- 失败 --> G["🟩 Revert & 写入失败记录"]

```

---

## 🔧 主要函数说明（简明）

| 函数名                   | 用途          | 参数类型/格式                                         |
| ------------------------ | ------------- | ----------------------------------------------------- |
| `createChapter(...)`     | 创建 NFT 章节 | 标题/描述/数量/URI（详见上文）                        |
| `freeMint()`             | 单个铸造 NFT  | `(address to, uint256 tokenId, uint256 amountMinted)` |
| `investorRegistration()` | 注册投资者    | `(address investor, uint256 tokenId)`                 |

### 🧑‍🎨 `createChapter(...)`

**功能**：创作者创建漫画章节，铸造 80% 的份额给创作者，平台默认保留 1 份。

**函数签名**

```solidity

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
) external returns (uint256);

```

**参数说明**

|参数名|类型|含义|
|---|---|---|
|mangaTitleZh|string|中文标题|
|mangaTitleEn|string|英文标题|
|mangaTitleJp|string|日文标题|
|descriptionZh|string|中文描述|
|descriptionEn|string|英文描述|
|descriptionJp|string|日文描述|
|maxCopies|uint256|NFT 最大数量（必须为 10 的倍数）|
|uri\_|string|章节元数据的 IPFS 链接|
|creator_addr|address|创作者的地址|


**调用权限**：任何用户（通常为创作者）

**前端数据存储与更新建议**

- **NFT 相关**:

- `tokenId`： NFT 的链上 ID，用于后续追踪。

- `mangaTitleZh`：中文标题

- `mangaTitleEn`：英文标题

- `mangaTitleJp`：日文标题

- `descriptionZh`：中文描述

- `descriptionEn`：英文描述

- `descriptionJp`：日文描述

- `maxCopies`：此次发布的数量

- `mintTime`: 发布时间

- `supplyBalance`: NFT 可铸造的数量，运算逻辑为`supplyBalance=maxCopies-1-maxCopies*4/5`

- **创建者相关**:

- `tokenId`: NFT 的链上 ID

- `maxCopies`：此次发布的数量

- `onhandBalance`: 已持有数量，运算逻辑为`onhandBalance=maxCopies*4/5`

说明： 虽然上述信息均可上链存储，但是为了节约 gas 费用，所以建议前端同步存储数据。

**事件**

- `ChapterCreated(...)`

```solidity

event ChapterCreated(
	uint256 indexed tokenId,
	address indexed creator,
	string mangaTitleZh,
	string mangaTitleEn,
	string mangaTitleJp
);

```

- `ChapterMinted(...)`

```solidity

event ChapterMinted(
	uint256 indexed tokenId,
	address indexed to,
	uint256 amountMinted,
	uint256 mintTime
);

```

**前端注意事项**

- 要监听 `ChapterCreated` 和 `ChapterMinted` 事件获取 tokenId 和 mint 结果。

- 建议限制 `maxCopies` 为 10, 20, 30... 等合法值。

- IPFS CID 应符合 URI 格式，如 `ipfs://...`

---

### 🔄 `freeMint(...)`

**功能**：平台单独铸造 NFT，指定数量及接收者角色。

**函数签名**

```solidity

function freeMint(
	address to,
	uint256 tokenId,
	uint256 amountMinted
) public onlyPlatform;

```

**参数说明**

|参数名|类型|含义|
|---|---|---|
|to|address|接收者地址|
|tokenId|uint256|要铸造的 NFT ID|
|amountMinted|uint256|铸造份额数量|

**调用权限**：仅平台

**事件**

- `ChapterMinted(...)`

**前端注意事项**

- 自动添加投资人记录

---

### 💼 `investorRegistration(...)`

**功能**：平台在投资者已收到 NFT 后登记其身份为投资人

**函数签名**

```solidity

function investorRegistration(address investor, uint256 tokenId) public onlyPlatform;

```

**参数说明**

|参数名|类型|含义|
|---|---|---|
|investor|address|投资者地址|
|tokenId|uint256|NFT ID（投资者持有的）|

**调用权限**：仅平台

**效果**

- 校验该投资者是否真的持有该 NFT

- 更新投资者身份信息

**前端注意事项**

- 在私下交易或超时自动确认时由平台调用

- 若 `balanceOf` 不满足条件，将 revert：`Investor does not hold this NFT`

---

## ⚠️ 注意事项


- 所有 `struct[]` 需按 ABI 正确编码

- 所有 mint 函数都受 `onlyPlatform` 限制

- 合约已包含多语言支持与角色注册逻辑

- 推荐事件监听而非主动查询以节省链上读开销

- 代币追踪逻辑已迁移到 `MonthlyDataUploader` 合约中

- 两个合约之间存在循环依赖，部署时需要使用提供的部署脚本

