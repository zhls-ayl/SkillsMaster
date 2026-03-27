# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- 发布链路新增多产物矩阵：GitHub Release 现在可以同时提供 `universal.zip`、`arm64.zip`、`x86_64.zip` 与 `universal.dmg`，为通用安装、单架构下载和 DMG 拖拽安装提供不同选择。

### Changed
- 打包脚本新增单架构与整套 release 产物输出能力；应用内自更新在多 zip 资产场景下会继续优先选择 `universal.zip`，避免误下载到单架构包。

## [0.2.4] - 2026-03-27
### Fixed
- 修复应用内“立即更新”在真实安装场景下不会真正替换当前 `.app` 的问题。更新器现在会在退出当前进程后执行带回滚的 bundle 替换；安装在 `/Applications` 等受保护目录时会申请管理员权限，而在 App Translocation / 只读卷 / 非 `.app` 启动场景下会明确报错，不再静默失败。

## [0.2.3] - 2026-03-27
### Added
- 各类 Skill 详情页新增手动 `翻译` 按钮，为不启用自动翻译的用户提供按需查看当前 Skill 中文译文的入口；点击后会复用现有内联翻译链路，但不会修改全局自动翻译设置。

### Changed
- 手动翻译现在覆盖 `Installed` 下的 `All Skills` 与 `Agents Skills`，以及 `Skills.sh`、ClawHub、SkillsHub、`Repositories` 的详情页；翻译状态在同一详情视图内切换 Skill 时会保留，再次点击工具栏中的 `翻译` 按钮可恢复原文。
- 手动翻译按钮在显示译文时会进入高亮态，帮助用户识别当前处于“已开启翻译、再次点击可恢复原文”的交互状态。

## [0.2.2] - 2026-03-27
### Added
- 新增 Skill 详情页内联中文翻译能力：本地 Skill、`Skills.sh`、ClawHub、SkillsHub 与 Custom Repository 的 Markdown 文档在系统支持且已安装 English -> Simplified Chinese 离线翻译包时，会在英文段落下方显示中文译文。
- 新增本地翻译相关基础能力与测试，包括翻译服务缓存、Markdown 段落纯文本提取、语言包提示策略，以及并发去重 / 串行化测试。
- 在 `Settings > 通用` 中新增 `自动翻译` 开关，可直接关闭详情页 Markdown 文档的内联中文翻译。
- 在 `Settings` 中新增独立的“翻译”设置页，位于 `Repositories` 之后、`关于` 之前，用于集中管理自动翻译配置。
- 自动翻译新增细粒度生效范围设置，支持分别控制 `Installed`、`Skills.sh`、`ClawHub`、`SkillsHub`、`Repositories` 与 `Agents Skills`。

### Changed
- 调整详情页 Markdown 渲染策略：仅在启用中文翻译时退回稳定的非 lazy 栈布局，并关闭这一路径上的隐式动画，降低滚动过程中的动态高度重排风险。
- 更新 README 中对详情页中文翻译能力和额外系统要求的说明。
- Skill 详情页的自动翻译能力现在同时受系统翻译包可用性和用户设置控制；关闭开关后会立即回退为只显示原始文档。
- 自动翻译默认值改为关闭，且各翻译范围默认均为关闭；用户需在新设置页中显式启用后才会生效。
- `Agent Files` 中的文件预览明确不纳入自动翻译范围，仅各类 Skill 详情页会参与范围判断。

### Fixed
- 修复启用中文翻译后在 Skill 详情页滚动长文档时容易触发重复翻译任务、布局抖动，进而在 `Skills.sh -> vercel-react-best-practices` 等长内容详情页出现卡死的问题。
- 修复同一段文本在并发场景下可能被重复提交给本地翻译框架的问题；现在会对相同文本做 in-flight 去重，并对不同段落的翻译请求做串行化收敛。

## [0.2.1] - 2026-03-24
### Changed
- 统一 `Skills.sh`、`SkillsHub`、`ClawHub` 与 `Custom Repository` 的安装交互：移除列表行直接安装与 `skills.sh` / 自定义仓库的 sheet 流程，统一改为详情页内联 Agent 勾选安装。
- 扩展 ClawHub 安装目标，不再固定为 `OpenClaw`，改为与其它来源一样支持多 Agent 选择。

### Fixed
- 修复不同来源下安装 / 重装按钮文案与实际勾选目标不一致的问题；主按钮现在会根据已选 Agent 的 direct install 状态显示 `Install`、`Reinstall` 或 `Install / Reinstall`。
- 修复已显示 `Reinstall` 时默认不勾选已安装 Agent、导致用户难以判断影响范围的问题；现在进入详情页时会默认勾选该 Skill 已直接安装的 Agent。

## [0.2.0] - 2026-03-24
### Added
- 新增 `SkillsHub` 独立 marketplace 入口，位于 `Marketplace` 分组下，与 `Skills.sh`、`ClawHub` 并列；支持分类、搜索、排序和分页浏览。
- 新增 SkillsHub archive 详情链路：详情页会直接解析下载包中的 `SKILL.md` 与 `_meta.json`，不再依赖网页摘要字段近似显示。
- 新增 SkillsHub 安装链路，可将选中的 skill 安装到任意已支持 Agent，而不是受限于单一 Agent。
- 新增 SkillsHub 专题文档 `docs/skillhub.md`，并补充对应的模型 / ViewModel / lock file 测试。

### Changed
- 扩展 `LockEntry`，新增 `sourceVersion`、`sourceUpdatedAt`、`originSourceType`、`originSource`、`originSourceUrl` 等 optional 字段，用于承载 marketplace 版本与 upstream 来源语义，同时保持对旧 lock file 的兼容读取。
- 调整 Skill 详情页的包信息区与更新状态逻辑，使 marketplace 来源不再被强行按 Git repository 语义展示；`SkillsHub` 已安装 skill 会显示版本级更新信息而不是 Git hash。
- `refresh()` 现在会保留已检查出的远端更新目标信息，避免刷新后出现“仍显示有更新，但目标版本 / hash 已丢失”的状态漂移。

### Fixed
- 修复 Homebrew cask 版本元数据与当前发布版本不同步的问题，更新至 `0.2.0` 并对齐新的 release zip `sha256`。
- 修复 SkillsHub 详情页渲染参数与当前 `MarkdownContentView` 接口不一致的问题。
- 修复 SkillsHub 详情页在 `Skill Metadata` 有内容时会被错误嵌套在 `Skill Content` section 下的问题；现在 `Skill Metadata` 会作为独立 section 显示，不再出现两个 section 标题直接相邻的布局错误。
- 修复原生 Markdown 表格在横向滚动场景下使用无界宽度导致的高 CPU 布局热点。`MarkdownTableView` 现在改为最小列宽 + 有界对齐，避免像 `Multi Search Engine` 这类包含多张表格的 skill 在详情页触发 CPU 100% 卡死。

## [0.1.9] - 2026-03-23
### Changed
- 重组左侧 Sidebar 信息架构：顶层分组统一为 `Installed`、`Marketplace`、`Repositories`、`Agents`；其中主列表入口改名为 `All Skills`，在线来源改为 `Skills.sh` / `ClawHub`，并将 `Agent Files` 调整到 `Agents Skills` 之前，降低导航扫描成本。
- 同步调整 `Agents` 分组中的命名与层级说明，使 `Agent Files`、`Agents Skills` 与对应详情模式保持一致，减少原有 `Dashboard` / `Registry` / `Custom Repos` 混用带来的理解成本。

### Fixed
- 对齐导航内部语义命名：将 `Dashboard`、`customRepo`、`agentSkills` 等旧选择态与视图 / ViewModel 命名统一到 `All Skills`、`repository`、`skillsByAgent` 等当前结构，降低后续维护时 UI 文案与代码语义再次漂移的风险。

## [0.1.8] - 2026-03-23
### Fixed
- 修复 Dashboard Skill 详情页工具栏中的 Finder 文件夹按钮会错误打开无关目录的问题。现在详情页会稳定定位到当前 Skill 的实际目录，不再落到下载目录等偏移位置。
- 统一 Dashboard 列表右键 `Open in Finder` 与 Skill 详情页文件夹按钮的 Finder 打开逻辑，改为复用同一条 reveal 链路，并在目标路径缺失时自动回退到最近存在的父目录。

## [0.1.7] - 2026-03-23
### Added
- 新增 `Agent Files` 视图，支持按 Agent 浏览配置根目录文件树，并对 `skills/` 及其子树维持只读保护；同时提供隐藏文件显示、新建文件 / 文件夹、重命名、删除，以及在 Finder / 终端中打开当前项的能力。
- 新增内置纯文本预览与编辑能力，覆盖 `SKILL.md`、`.md`、`.json`、`.toml`、`.txt`、`.yaml`、`.yml`、`.log` 等文本文件；支持全局外置编辑器和默认终端偏好设置，并可直接从应用内跳转。

### Changed
- 调整 `Agents > Skills` 详情模式：从 Agent 侧边栏进入时，详情页改为只读内容视图，仅展示标题、描述、Metadata 与 Markdown 正文；完整管理入口继续保留在 Dashboard 详情面板中。
- 优化 `Agent Files` 文件树加载策略，改为按需 lazy load 子目录，减少首次展开大目录时的阻塞。
- `Agent Files` 中的文本文件会优先在右侧 detail pane 直接预览；Markdown 使用原生渲染，其他文本使用等宽格式化预览，超过 10 MB 时自动降级为原始文本预览。

### Fixed
- 修复旧版 root-skill 安装遗留物不会自动清理的问题，应用启动时现在会清除已被 canonical `skills/` 目录取代的历史根层文件，避免 Agent 根目录长期残留重复产物。
- 修复 `Agent Files` 对目录 symbolic link 的识别问题，当前可正确把目录链接视为可展开目录，而不是普通文件。

## [0.1.6] - 2026-03-22
### Fixed
- 修复 Registry 中部分 Skill 的 `Skill Content` 无法加载并显示 `Network error: The network connection was lost` 的问题。`SkillContentFetcher` 现在会在 `raw.githubusercontent.com` 不可达时自动回退到 GitHub Contents API，避免正文加载链路被 raw CDN 连接问题直接中断。
- 修复 `skills.sh` 展示 slug 与 GitHub 仓库实际目录名不一致时 Registry 详情页容易取不到正文的问题。现有路径猜测逻辑保留，同时继续通过 Git Tree fallback 查找真实 `SKILL.md` 路径，以兼容像 `remotion-best-practices -> skills/remotion/SKILL.md` 这类映射。

## [0.1.5] - 2026-03-22
### Added
- 新增每个 Agent 独立的默认安装方式配置，支持在 `软链接` 与 `物理复制` 之间持久化切换，并在设置变更后立即迁移该 Agent 当前由 SkillsMaster 管理的 direct install。

### Changed
- SkillsMaster 继续以 canonical 目录作为事实源，但 Agent 目录现在可按默认策略 materialize 为 symbolic link 或同步 physical copy；相关安装、重新安装、更新与应用内编辑流程都会同步覆盖 physical copy。
- 优化“Agent 默认安装方式”设置区的布局：去掉重复 Agent 标签，统一名称与 segmented control 的列对齐，并将 segmented control 贴右放置。
- 调整设置页与主界面侧边栏 `Agents` 区的排序规则，统一按 Agent 名称长度升序、同长度按字母顺序排列，减少视觉参差。

### Fixed
- 修复物理复制模式下 direct install 无法跟随详情页编辑、重新安装与更新流程同步覆盖的问题。
- 修复 Agent 分配在 physical copy 场景下只会删除 symbolic link、不会清理真实目录的问题。

## [0.1.4] - 2026-03-20
### Changed
- 重构 Skill 详情页的 front matter 展示方式：头部仅保留名称与简短描述，新增结构化 `Skill Metadata` 区块，单独展示 YAML 中未被专门 UI 覆盖的 key/value，避免原始 front matter 整块重复堆叠在详情页中。
- 统一本地 Skill、Repository、Registry 与 ClawHub 详情页的 metadata 展示逻辑，`author`、`version`、`license` 继续作为独立字段展示，其余复杂嵌套值按格式化文本块呈现。

### Fixed
- 修复从 GitHub 安装 root-level skill 时目录解析错误的问题。现在当 repository 根目录直接包含 `SKILL.md` 时，安装流程会正确保留仓库根路径，不再把目录内容错误复制成前缀污染文件。

## [0.1.3] - 2026-03-20
### Changed
- 优化 ClawHub 安装体验：安装按钮会显示更细粒度的阶段状态，例如加载 package 信息、下载 archive、等待 ClawHub rate limit 恢复、重试下载、获取 `SKILL.md` 和本地安装阶段，避免长时间只显示笼统的 `Installing...`。
- 优化 ClawHub 已安装技能的恢复路径：对于已通过 ClawHub 安装的技能，列表页与详情页都允许执行 `Reinstall`，用于在先前 markdown-only 安装后补齐 auxiliary files。

### Fixed
- 修复 ClawHub archive 下载遇到短时 `retry-after` 限流时，应用立即退化为 markdown-only 安装的问题。现在会在合理窗口内按服务端提示等待一次并自动重试。

## [0.1.2] - 2026-03-20
### Fixed
- 修复 ClawHub 浏览列表在当前站点协议下始终为空的问题。根因是 SkillsMaster 仍依赖旧的 `GET /api/v1/skills` 返回模型，而线上 ClawHub 已切换到 Convex public query。
- 修复 ClawHub 详情与 `SKILL.md` 加载链路对旧接口的依赖，改为对齐当前网站正在使用的详情查询与内容 action，避免详情面板加载失败或内容缺失。
- 修复 ClawHub 搜索链路与线上实现漂移的问题。主路径改为当前网站使用的搜索 action，同时保留旧 REST 搜索作为 fallback，降低上游再次变更时的回归风险。
- 修复 ClawHub browse 分页策略过时的问题。浏览模式改为使用服务端返回的 cursor 分页，而不是持续放大 `limit` 去重拉“前 N 条”。
