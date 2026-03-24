# SkillsHub 功能设计与工作原理

本文记录当前仓库中 SkillsHub 功能的真实实现，覆盖入口、模型、浏览接口、archive 详情、安装落盘、来源记录与更新语义。若代码与本文不一致，以 `Sources/` 与 `Tests/` 中当前实现为准，并在修改后同步更新本文。

## 功能定位
SkillsHub 在 SkillsMaster 中是第三条独立 marketplace 链路，与 `Skills.sh`、`ClawHub` 并列，不复用它们的模型或 service。

当前设计目标是：
- 在应用内浏览 SkillsHub marketplace
- 按分类、搜索词、排序与分页查看 SkillsHub skills
- 从 archive 中解析 `SKILL.md` 供详情页渲染
- 将选中的 SkillsHub skill 安装到 SkillsMaster canonical 目录
- 按用户选择的目标 Agent 集合，把 skill 落到任意已支持 Agent 的目录
- 对已通过 SkillsHub 安装的 skill 提供版本级更新检查与更新动作

## 入口与界面组织
SkillsHub 通过 `SidebarItem.skillsHub` 作为独立导航项暴露在侧边栏，位于 `Marketplace` 分组下，与 `Skills.sh`、`ClawHub` 同级。

对应 UI 结构如下：
- 左栏：`SidebarView` 提供 `SkillsHub` 导航项
- 中栏：`SkillsHubBrowserView` 展示分类、排序、分页控件以及 skill 列表
- 右栏：`SkillsHubSkillDetailView` 展示选中 skill 的 package 信息、目标 Agent 选择、安装按钮与解析后的 `SKILL.md`

`ContentView` 会在应用初始化时创建 `SkillsHubBrowserViewModel`，并在用户切换到 `SkillsHub` 页面时复用该 ViewModel。

相关实现：
- `Sources/SkillsMaster/Views/Sidebar/SidebarView.swift`
- `Sources/SkillsMaster/Views/ContentView.swift`
- `Sources/SkillsMaster/ViewModels/SkillsHubBrowserViewModel.swift`
- `Sources/SkillsMaster/Views/Registry/SkillsHubBrowserView.swift`
- `Sources/SkillsMaster/Views/Registry/SkillsHubSkillDetailView.swift`

## 分层设计
SkillsHub 功能按以下层次实现：

### 1. Model 层
`SkillsHubSkill` 与 `SkillsHubSkillDetail` 是 SkillsHub 专用模型，独立于 `RegistrySkill` 与 `ClawHubSkill`。

`SkillsHubSkill` 承载列表展示所需数据：
- `slug`
- `displayName`
- `summary`
- `localizedSummary`
- `category`
- `downloads`
- `installs`
- `stars`
- `score`
- `latestVersion`
- `homepageURLString`
- `ownerName`
- `updatedAtMilliseconds`
- `tags`

它还提供面向 UI 的计算属性：
- `descriptionText`：优先使用中文描述，其次回退到原始 summary
- `formattedDownloads` / `formattedInstalls` / `formattedStars`
- `formattedUpdatedDate`
- `originSourceType` / `originSource` / `originSourceURL`：当前通过 `homepage` 推断上游来源

`SkillsHubSkillDetail` 在列表模型之上补充 archive 解析结果：
- `content`：解析后的 `SKILL.md` 内容
- `archiveMetadata`：`_meta.json` 中的补充信息
- `extractedFiles`

`installVersion` 的优先级为：
1. archive `_meta.json` 中的 `version`
2. 列表接口中的 `latestVersion`

### 2. Service 层
`SkillsHubService` 是 SkillsHub API 与 archive 下载的唯一入口，被实现为 `actor`。

公开 API 包括：
- `fetchSkills(options:)`
- `fetchFeaturedSkills()`
- `searchSkills(query:limit:)`
- `fetchSkill(slug:)`
- `fetchSkillDetail(slug:seed:)`
- `downloadSkillArchive(slug:)`
- `clearCache()`

它内部维护了三类 cache：
- `featuredCache`
- `detailCache`
- `archiveCache`

这样在详情页解析过 archive 后，再执行安装时不会重复下载同一个 zip。

### 3. ViewModel 层
`SkillsHubBrowserViewModel` 负责把浏览、详情加载和安装操作编排成一套页面状态。

核心状态包括：
- 列表状态：`searchText`、`selectedCategory`、`selectedSort`、`displayedSkills`
- 分页状态：`currentPage`、`totalCount`
- 详情状态：`selectedSkillID`、`selectedSkillDetail`、`detailError`
- 安装状态：`selectedTargetAgents`、`installingSkillSlug`、`installingStatusMessage`
- 用户提示：`notice`

### 4. Manager / 文件系统层
SkillsHub 不直接写 SkillsMaster 的 canonical 目录。真正的落盘动作由 `SkillManager.installSkillsHubSkill(...)` 执行，职责包括：
- 下载并解压 zip archive
- 递归定位包含 `SKILL.md` 的目录
- 复制到 SkillsMaster canonical 目录
- 按目标 Agent 的默认安装方式建立 direct install
- 写入 lock file
- 刷新扫描结果回到 UI

## API 对接与数据来源

### 浏览列表
SkillsHub 列表页当前使用网站接口：

- `GET https://lightmake.site/api/skills`

请求参数包括：
- `page`
- `pageSize`
- `sortBy`
- `order`
- `keyword`
- `category`

当前实现对齐到站点正在使用的参数语义：
- 默认 `pageSize = 24`
- 默认排序 `score desc`
- 搜索和浏览共用同一个列表接口

### 精选列表
精选 badge 通过以下接口获取：

- `GET https://lightmake.site/api/skills/top`

当前实现不会单独渲染一个“精选页面”，而是把返回的 slug 集合用于列表和详情中的 `Featured` 标记。

### 轻量搜索
SkillsHub CLI 当前使用另一条轻量搜索接口：

- `GET https://lightmake.site/api/v1/search?q=<query>&limit=<limit>`

SkillsMaster 当前主要在以下场景使用这条接口：
- 根据 slug 做精确回退查找
- 为安装 / 更新链路补充最小版本信息

### archive 下载
安装与详情解析使用 SkillsHub 当前 archive 下载接口：

- `GET https://lightmake.site/api/v1/download?slug=<slug>`

该接口会返回 zip archive。当前实测 archive 中可能包含：
- `SKILL.md`
- `_meta.json`
- 额外的 `scripts/`
- 额外的 `reference/`
- 其他辅助文件

SkillsMaster 会优先把 archive 视为安装事实源，而不是依赖网页列表字段去推导本地文件内容。

## 详情加载策略
SkillsHub 当前没有独立的 `getReadme` 或 detail metadata API；因此详情页采用 archive-first 策略：

1. 根据当前选中项拿到 slug
2. 下载 zip archive
3. 解压到临时目录
4. 递归定位包含 `SKILL.md` 的目录
5. 读取并解析 `SKILL.md`
6. 如存在 `_meta.json`，则补充 `version` / `publishedAt` / `ownerId`
7. 如 frontmatter 解析失败，则回退为 markdown-only 展示

这保证了详情页看到的内容与实际可安装内容一致，而不是网页展示层的近似摘要。

## 安装落盘与来源记录
安装 SkillsHub skill 时，SkillsMaster 会写入 `~/.agents/.skill-lock.json`，并使用以下语义：

- `source = <slug>`
- `sourceType = "skillhub"`
- `sourceUrl = "https://skillhub.tencent.com/"`
- `sourceVersion = 当前安装版本`
- `sourceUpdatedAt = SkillsHub 列表接口中的更新时间（ISO 8601）`

同时还会尽量记录推断出的 upstream 来源：
- `originSourceType`
- `originSource`
- `originSourceUrl`

当前推断规则是：
- 若 `homepage.host == clawhub.ai`，则 `originSourceType = "clawhub"`
- `originSource` 优先从 `homepage` path 推导，例如 `owner/slug`

注意：当前 SkillsHub 数据里没有显式的 upstream 字段，因此这部分语义属于“基于网站现状的稳定推断”，不是官方字段直读。

## 更新语义
SkillsHub 不走 Git tree hash 更新检查，而是走 version 语义：

1. 读取 lock entry 中的 `sourceVersion`
2. 通过 slug 获取远端最新 `latestVersion`
3. 使用 `VersionComparator` 做版本比较
4. 若远端版本更新，则标记 `hasUpdate`
5. 执行更新时重新下载 archive，并覆盖 canonical 目录

更新完成后会：
- 更新 lock entry 的 `sourceVersion`
- 更新 `sourceUpdatedAt`
- 同步刷新推断出的 upstream 字段

## 当前限制与已知边界
- SkillsHub 浏览层与安装层并不是同一套数据源。浏览主要看 `api/skills`，安装主要看 `api/v1/download`
- SkillsHub 自带 CLI 当前偏向 `OpenClaw` 工作区与 plugin 注入，不适合作为 SkillsMaster 面向全部 Agent 的安装执行器
- `skills.json` 当前只有 50 条，不是全量 marketplace 索引，因此 SkillsMaster 不使用它做主浏览列表
- SkillsHub 当前 detail 内容依赖 archive 解析，没有独立详情 API
- upstream 来源当前只能通过 `homepage` 推断；如果站点后续新增显式字段，优先切换到显式字段

## 相关实现文件
- `Sources/SkillsMaster/Models/SkillsHubSkill.swift`
- `Sources/SkillsMaster/Services/SkillsHubService.swift`
- `Sources/SkillsMaster/Services/MarketplaceServiceProtocols.swift`
- `Sources/SkillsMaster/ViewModels/SkillsHubBrowserViewModel.swift`
- `Sources/SkillsMaster/Views/Registry/SkillsHubBrowserView.swift`
- `Sources/SkillsMaster/Views/Registry/SkillsHubSkillDetailView.swift`
- `Sources/SkillsMaster/Services/SkillManager.swift`
- `Tests/SkillsMasterTests/SkillsHubServiceModelTests.swift`
- `Tests/SkillsMasterTests/SkillsHubBrowserViewModelTests.swift`
