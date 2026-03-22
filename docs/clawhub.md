# ClawHub 功能设计与工作原理

本文记录当前仓库中 ClawHub 功能的真实实现，覆盖入口、模型、API 对接、分页、详情加载、安装落盘与限制条件。若代码与本文不一致，以 `Sources/` 与 `Tests/` 中当前实现为准，并在修改后同步更新本文。

## 功能定位
ClawHub 在 SkillsMaster 中是一个独立的在线来源，不复用 `Registry` 的实现，也不是通用 repository 浏览器的一个变体。当前设计目标是：
- 在应用内浏览 ClawHub marketplace
- 搜索、排序、筛选并查看 skill 详情
- 拉取 `SKILL.md` 供详情页渲染
- 将选中的 ClawHub skill 安装到 SkillsMaster canonical 目录
- 按 `OpenClaw` 的默认安装方式，把 skill 落到其目录中，使其可直接使用该 skill

当前实现明确面向 `OpenClaw`，不是面向所有 Agent 的通用安装入口。

## 入口与界面组织
ClawHub 通过 `SidebarItem.clawHub` 作为独立导航项暴露在侧边栏，和 `Dashboard`、`Registry`、`Custom Repos` 平级。

对应 UI 结构如下：
- 左栏：`SidebarView` 提供 `ClawHub` 导航项
- 中栏：`ClawHubBrowserView` 展示浏览列表、搜索框、排序/筛选控件、分页状态
- 右栏：`ClawHubSkillDetailView` 展示选中 skill 的 package 信息、解析后的 `SKILL.md` metadata、正文内容与安装按钮

`ContentView` 会在应用初始化时创建 `ClawHubBrowserViewModel`，并在用户切换到 `ClawHub` 页面时复用该 ViewModel。

相关实现：
- `Sources/SkillsMaster/Views/Sidebar/SidebarView.swift`
- `Sources/SkillsMaster/Views/ContentView.swift`
- `Sources/SkillsMaster/Views/Registry/ClawHubBrowserView.swift`
- `Sources/SkillsMaster/Views/Registry/ClawHubSkillDetailView.swift`

## 分层设计
ClawHub 功能按以下层次实现：

### 1. Model 层
`ClawHubSkill` 和 `ClawHubSkillDetail` 是 ClawHub 专用模型，独立于 `RegistrySkill`。

拆开建模的原因是 ClawHub API 的字段语义与 `skills.sh` 不同，例如：
- 主键使用 marketplace `slug`
- 列表和搜索返回的字段集不同
- 详情页包含版本、license、moderation 等额外信息

`ClawHubSkill` 负责承载列表展示所需数据：
- `slug`
- `displayName`
- `summary`
- `latestVersion`
- `downloads`
- `stars`
- `versionCount`
- `ownerHandle`
- `ownerDisplayName`
- `updatedAtMilliseconds`

它还提供了几个面向 UI 的计算属性：
- `id`：直接等于 `slug`
- `name`：优先使用裁剪后的 `displayName`，为空时回退到 `slug`
- `descriptionText`：优先使用 `summary`，为空时给出兜底文案
- `browserURL`：若已知 `ownerHandle`，指向 `https://clawhub.ai/<ownerHandle>/<slug>`；否则退化到 `https://clawhub.ai/skills?focus=search&q=<slug>`
- `formattedDownloads` / `formattedStars` / `formattedUpdatedDate`：用于展示格式化结果

`ClawHubSkillDetail` 在列表模型之上补充详情字段：
- `latestVersion`
- `latestVersionID`
- `latestVersionCreatedAt`
- `latestChangelog`
- `license`
- `moderationVerdict`
- `moderationSummary`

其中 `installVersion` 是安装动作使用的版本号，优先级为：
1. 详情接口中的 `latestVersion`
2. 列表模型中的 `skill.latestVersion`

这样可以避免只依赖列表页的粗粒度版本信息。

### 2. Service 层
`ClawHubService` 是 ClawHub API 的唯一入口，被实现为 `actor`。

采用 `actor` 的目的有两个：
- 让网络请求状态和缓存访问天然串行化
- 让 `detailCache`、`contentCache` 这类共享缓存不需要额外锁

公开 API 只有 5 个：
- `fetchSkills(options:)`
- `searchSkills(query:limit:)`
- `fetchSkillDetail(slug:)`
- `fetchSkillContent(slug:)`
- `downloadSkillArchive(slug:version:)`

同时通过 `ClawHubServiceProtocol` 抽象出最小接口，供 `ClawHubBrowserViewModel` 注入和测试替身使用。这样 ViewModel 测试不需要真实网络请求。

### 3. ViewModel 层
`ClawHubBrowserViewModel` 负责把浏览、搜索、详情加载和安装操作编排成一套页面状态。

它维护的核心状态包括：
- 列表搜索与筛选状态：`searchText`、`selectedSort`、`selectedDirection`、`highlightedOnly`、`nonSuspiciousOnly`
- 列表结果状态：`displayedSkills`、`isLoading`、`errorMessage`
- 分页状态：`isLoadingMore`、`loadMoreErrorMessage`、`hasMoreResults`、`nextBrowseCursor`、`currentSearchLimit`
- 详情状态：`selectedSkillID`、`selectedSkillDetail`、`fetchedContent`、`detailError`、`contentError`
- 安装状态：`installingSkillSlug`
- 用户提示：`notice`

### 4. Manager / 文件系统层
ClawHub 不直接写文件。真正的落盘动作由 `SkillManager.installClawHubSkill(...)` 执行，职责包括：
- 构建临时目录
- 解压 archive 或写入 markdown-only 目录
- 复制到 SkillsMaster canonical 目录
- 按目标 Agent 的默认安装方式创建 direct install（symbolic link 或 physical copy）
- 写入 lock file
- 触发 `refresh()` 让扫描结果回到 UI

## API 对接与请求语义

### 浏览列表
浏览模式不再依赖 `GET /api/v1/skills`，而是改为调用 ClawHub 当前网页同源的 Convex public query：

- `POST https://wry-manatee-359.convex.cloud/api/query`
- `path = "skills:listPublicPageV4"`
- `format = "convex_encoded_json"`

请求参数由 `ClawHubService.BrowseOptions` 统一编码为 request body，当前支持：
- `cursor`
- `numItems`
- `sort`
- `dir`
- `highlightedOnly`
- `nonSuspiciousOnly`

其中：
- `numItems` 默认 50
- 默认排序改为 `downloads`
- `name` 默认方向为 `asc`
- 其他排序默认方向为 `desc`

当前 UI 暴露的 browse sort 与网站现状保持一致：
- `downloads`
- `newest`
- `updated`
- `installs`
- `stars`
- `name`

`fetchSkills(options:)` 返回的不是单纯数组，而是 `BrowsePage`：
- `items`
- `nextCursor`
- `hasMore`

这样 ViewModel 可以按 server 提供的 cursor 继续加载，而不是重复请求“前 N 条”。

### 搜索
搜索模式优先调用 ClawHub 当前网页使用的 action：

- `POST https://wry-manatee-359.convex.cloud/api/action`
- `path = "search:searchSkills"`
- `format = "convex_encoded_json"`

参数包括：
- `query`
- `highlightedOnly`
- `nonSuspiciousOnly`
- `limit`

当前实现出于可用性考虑保留了旧 REST fallback：
- 若 Convex action 失败，则退回 `GET /api/v1/search?q=<query>&limit=<limit>`

与旧实现相比，新的搜索结果通常能带回更完整的信息：
- `owner`
- `ownerHandle`
- `downloads`
- `stars`
- `versionCount`

只有在 fallback 到旧 REST 时，才会退化为较少字段的 `ClawHubSkill`。

### 详情
详情同样对齐到 ClawHub 当前网页的数据源：
- `POST https://wry-manatee-359.convex.cloud/api/query`
  `path = "skills:getBySlug"`，按 `slug` 获取 detail metadata
- `POST https://wry-manatee-359.convex.cloud/api/action`
  `path = "skills:getReadme"`，按 `latestVersionID` 获取 `SKILL.md` 原文

`fetchSkillDetail` 会把结果缓存到 `detailCache`。
`fetchSkillContent` 会把非空的 UTF-8 文本缓存到 `contentCache`。

缓存的目标不是做复杂离线能力，而是：
- 减少重复详情请求
- 降低频繁切换选中项时的等待
- 尽量减少 ClawHub 侧 rate limiting 风险

### 下载 archive
安装时调用 `GET /api/v1/download?slug=<slug>&version=<version>` 下载 skill archive。

当前实现只校验 archive 数据是否为空，不额外解析 manifest 或校验版本签名。

## 错误处理设计
`ClawHubService.ServiceError` 明确区分以下情况：
- URL 构造失败
- 非 HTTP 响应
- 非 2xx 响应
- 429 rate limited
- archive 不可用
- `SKILL.md` 为空

其中 429 会尽量读取 `retry-after` header，向上层返回更明确的提示文案。

View 层对错误的呈现分为三类：
- 列表加载失败：中栏显示错误空态与重试按钮
- 详情 metadata 加载失败：详情页 package info 区域显示 warning
- `SKILL.md` 加载失败：详情页 content 区域显示错误并提供 “View on ClawHub instead”

## 列表加载与分页策略
当前实现把 browse 和 search 的分页策略拆开了：

### browse 模式
使用 ClawHub 返回的 `nextCursor`：
1. 初次加载时 `nextBrowseCursor = nil`
2. 发送 `numItems = 50`、`cursor = nil`
3. 收到 `page`、`nextCursor`、`hasMore`
4. 触底时带上上一次返回的 `nextCursor` 继续请求下一页
5. 把新页 append 到现有 `displayedSkills`

`hasMoreResults` 的判断直接跟随服务端：
- `hasMore == true`
- 且 `nextCursor != nil`

### search 模式
仍沿用增大 `limit` 的方式：
1. 初次搜索时 `currentSearchLimit = 50`
2. 触底时 `currentSearchLimit += 50`
3. 重新请求 `searchSkills(query:limit:)`
4. 用更大的完整结果替换当前搜索结果

为了避免旧请求覆盖新请求，ViewModel 使用 `listRequestVersion` 做并发保护：
- 每次 `fetchCurrentList(reset:)` 前自增版本号
- 请求返回后只有版本号仍匹配，结果才会写回状态

这可以防止以下问题：
- 快速切换排序后，旧排序结果晚回来覆盖新结果
- 快速输入搜索词时，旧搜索结果回写到当前页面

相关行为由 `ClawHubBrowserViewModelTests` 覆盖，包括：
- browse 模式下基于 `nextCursor` 追加第二页
- 搜索模式下继续使用更大的 `limit`
- 当 `hasMoreResults == false` 时不再继续请求

## 搜索与浏览的关系
当前设计中，“搜索”与“浏览筛选”是互斥模式：
- 当 `searchText` 为空时，页面处于 browse 模式，可以调整排序、方向和两个筛选条件
- 当 `searchText` 非空时，页面切换到 search 模式，顶部 browse controls 会隐藏
- 这时真正发出的请求是 `searchSkills(query:limit:)`，而不是带筛选条件的 `fetchSkills`

同时，搜索有 350ms debounce：
- 每次 `searchText` 变化时取消旧任务
- 等待 350ms
- 若任务未被取消，则重新拉取当前搜索结果

这样可以减少每个键击都触发网络请求。

## 详情加载流程
选中某个 skill 后，`ClawHubSkillDetailView` 会通过 `.task(id: skill.id)` 触发 `viewModel.loadSelection(for:)`。

`loadSelection(for:)` 的执行顺序是：
1. 记录 `currentDetailSlug`
2. 清空旧的 detail / content / error 状态
3. 拉取 detail metadata
4. 拉取 `SKILL.md`
5. 尝试用 `SkillMDParser` 解析 frontmatter
6. 若解析失败，则退化为：
   - 使用列表页已有的 `name` / `descriptionText` 兜底 metadata
   - 保留原始 markdown 正文

其中 `currentDetailSlug` 是关键保护：
- 如果用户在请求过程中切到另一个 skill
- 旧请求返回后会先比较目标 `slug`
- 不匹配则直接放弃写回状态

这避免了右侧详情内容串页。

## 安装流程
安装入口位于详情页，按钮文案固定为 `Install to OpenClaw`。这对应当前实现的真实限制：ClawHub 安装目标只有 `OpenClaw`。

完整安装链路如下：

### 1. ViewModel 准备安装数据
`performInstall(_:)` 的流程是：
1. 先拉取 detail，获取 `installVersion`
2. 尝试下载 archive
   - 若收到 `429 rate limited` 且 `retry-after <= 60s`，会按 header 等待一次并自动重试 archive
3. 尝试拉取 `SKILL.md`
4. 如果 archive 和 `SKILL.md` 都拿不到，安装失败
5. 否则调用 `skillManager.installClawHubSkill(...)`

这样设计的意义是：
- 优先安装完整 archive
- 若 archive 不可用，仍允许最小化安装 `SKILL.md`

### 2. SkillManager 处理 archive 安装
`installClawHubSkill(...)` 会先构建临时目录，并生成一个 `LockEntry`：
- `source = slug`
- `sourceType = "clawhub"`
- `sourceUrl = 详情页 URL`
- `skillPath = "<slug>/SKILL.md"`
- `skillFolderHash = ""`

当前 lock file 不记录 ClawHub 版本，也不记录 tree hash 语义，因此 `version` 参数只用于接口语义对齐，暂不写回 lock file。

当 archive 存在时，流程为：
1. 把 zip 写入临时目录
2. 使用系统自带 `/usr/bin/ditto -xk` 解压
3. 递归查找第一个包含 `SKILL.md` 的目录
4. 将该目录作为 skill 源目录持久化安装

### 3. markdown-only fallback
当 archive 不可用，但 `SKILL.md` 能拿到时：
1. 在临时目录下创建 `<slug>/SKILL.md`
2. 写入下载到的 markdown 文本
3. 用 `SkillMDParser` 验证它至少是可解析的 skill 文件
4. 作为仅含 `SKILL.md` 的目录继续安装

这种情况下会返回 `.installedSkillMarkdownOnly`，ViewModel 会显示提示：
- 已安装
- 但辅助文件未包含在内

这是当前实现中一个很重要的容错策略，避免因 ClawHub 未提供 zip 而完全无法安装。

如果后续限流恢复，已通过 ClawHub 安装的 skill 可以再次点击安装按钮执行 `Reinstall`，用于补齐先前因 rate limit 缺失的辅助文件。

### 4. 统一落盘
无论是 archive 还是 markdown-only，最终都走 `persistInstalledSkillDirectory(...)`：
1. 将 skill 目录复制到 `~/.skillsmaster/skills/<slug>`
2. 按目标 Agent 的默认安装方式把 skill 落到 Agent 目录
3. 确保 `~/.agents/.skill-lock.json` 存在
4. 写入或更新 lock entry
5. 调用 `refresh()` 让扫描结果返回 UI

因此，ClawHub skill 的“真实副本”不直接放在 Agent 目录里，而是放在 SkillsMaster canonical 目录里。

### 5. Agent 侧生效方式
当前安装目标写死为 `targetAgents: [.openClaw]`。

这意味着：
- canonical 目录在 `~/.skillsmaster/skills`
- OpenClaw skills 目录在 `~/.openclaw/skills`
- 最终由 SkillsMaster 按 OpenClaw 当前默认安装方式，把 canonical 内容 materialize 到 OpenClaw 目录

这与项目整体的“真实文件以 canonical 目录为事实源，Agent 目录可以是 symbolic link 或同步 physical copy”的架构保持一致。

## 本地状态识别
ClawHub 页面需要在列表和详情中判断某个 skill 是否已经安装。当前识别逻辑分两层：

### 1. 正常 ClawHub 安装
若本地 skill 的 `lockEntry.sourceType == "clawhub"`，则取 `lockEntry.source` 与 `ClawHubSkill.slug` 比较。

匹配则认为已安装。

### 2. 手工或旧数据兼容
若本地 skill 没有 `lockEntry`，则退化为比较本地 `skill.id` 与 `slug`。

这样可以兼容：
- 用户手工放入的同名 skill
- 旧数据尚未补齐 lock file 的情况

这套逻辑由 `ClawHubBrowserViewModelTests` 明确覆盖。

## 与全局架构的关系
ClawHub 虽然是独立功能，但它仍然复用项目的底层公共机制：
- `SkillMDParser`：解析 ClawHub 拉回的 `SKILL.md`
- `SkillManager`：统一安装与 refresh
- `SkillScanner`：扫描 canonical 目录和 Agent 目录，生成本地 Skill 列表
- `SymlinkManager`：识别 OpenClaw 目录中的 symbolic link / physical copy 以及继承关系
- `LockFileManager`：写入 `~/.agents/.skill-lock.json`

这意味着 ClawHub 在产品层面是单独链路，但在本地生命周期管理层面仍遵守 SkillsMaster 的主架构。

## 当前限制与边界
当前实现存在以下明确限制，修改前应先确认：

### 1. 仅支持安装到 OpenClaw
安装按钮、ViewModel 参数和最终 `targetAgents` 都明确写死为 `OpenClaw`。

如果将来要扩展为多 Agent 安装，需要同时修改：
- 详情页文案
- ViewModel 安装参数
- 安装结果提示
- 可能的 Agent 兼容规则与 UI 选择器

### 2. 不参与 Git 更新检查
ClawHub / Local 安装的 skill 不走 `checkForUpdate`：
- 单个更新检查会直接跳过 `sourceType == "clawhub"`
- 批量更新检查同样排除 `sourceType == "clawhub"`

原因是当前 lock file 记录的是 marketplace 来源，而不是 Git 仓库 tree hash。

### 3. lock file 只记录来源，不记录版本演进语义
当前 `LockEntry` 中：
- `source` 记录 slug
- `sourceUrl` 记录详情页地址
- `skillFolderHash` 留空

因此当前实现只能表达“这个 skill 来自 ClawHub”，不能表达“本地安装的是 ClawHub 的哪个已知可更新版本”。

### 4. archive 缺失时允许退化安装
这是产品上的有意选择，不是异常分支：
- 目标是尽量让 skill 可用
- 代价是辅助文件可能缺失

如果未来要把 archive 作为强依赖，应同步调整安装提示、错误语义和文档说明。

## 相关测试
当前与 ClawHub 直接相关的测试主要有两类：

### `ClawHubServiceModelTests`
覆盖：
- `ClawHubSkill` 的 URL 与格式化行为
- `ClawHubSkillDetail.installVersion` 的优先级
- `BrowseOptions` 到 Convex request body 的编码规则
- `name` 排序默认方向为 `asc`

### `ClawHubBrowserViewModelTests`
覆盖：
- 已安装判断逻辑
- browse 模式触底加载更多时的 cursor 续页
- 搜索模式触底加载更多时的 `limit` 递增
- 数据不足时停止继续加载

这些测试当前主要保障“状态编排正确”，不是端到端网络联调测试。

## 维护建议
- 改 ClawHub API 字段映射时，先同步检查 `ClawHubSkill` / DTO 转换和对应测试
- 改 browse API 时，优先核对当前网站 bundle 使用的 Convex function 与返回结构，再决定是否调整 DTO
- 改分页方式时，先区分 browse 的 cursor 和 search 的 limit，不要把两条链路重新混成一种策略
- 改安装目标时，先确认是否仍保持 `OpenClaw` 专用，还是升级为多 Agent 选择
- 改 lock file 记录方式时，先评估是否要把 ClawHub 版本信息纳入更新语义
- 改 markdown-only fallback 时，先确认产品预期是“尽量安装成功”还是“宁可失败也要完整文件”

## 关键实现位置
- `Sources/SkillsMaster/Models/ClawHubSkill.swift`
- `Sources/SkillsMaster/Services/ClawHubService.swift`
- `Sources/SkillsMaster/Services/MarketplaceServiceProtocols.swift`
- `Sources/SkillsMaster/ViewModels/ClawHubBrowserViewModel.swift`
- `Sources/SkillsMaster/Views/Registry/ClawHubBrowserView.swift`
- `Sources/SkillsMaster/Views/Registry/ClawHubSkillDetailView.swift`
- `Sources/SkillsMaster/Services/SkillManager.swift`
- `Tests/SkillsMasterTests/ClawHubServiceModelTests.swift`
- `Tests/SkillsMasterTests/ClawHubBrowserViewModelTests.swift`
