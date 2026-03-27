# 架构与实现边界

## 系统定位
SkillsMaster 是一个基于 SwiftUI 的 macOS 应用，用于管理多代理 Skills 的本地生命周期，以及各 Agent 配置根目录中的普通文件。它不是通用包管理器，也不是云端服务；核心职责是把本地目录、symbolic link / physical copy、lock file、Git 来源与 UI 操作统一起来。

## 实现结构
- `Sources/SkillsMaster/App/`：应用入口、主题应用、启动激活
- `Sources/SkillsMaster/Views/`：`NavigationSplitView` 三栏 UI 与可复用组件
- `Sources/SkillsMaster/ViewModels/`：页面状态与交互编排
- `Sources/SkillsMaster/Services/`：扫描、解析、lock file、Git、仓库、更新、迁移、文件监控
- `Sources/SkillsMaster/Models/`：Agent、Skill、Repository、LockEntry 等核心模型
- `Sources/SkillsMaster/Utilities/`：常量、扩展、版本比较等纯工具

其中与 Agent 根目录文件管理直接相关的代码目前包括：
- `Models/AgentType.swift`：定义各 Agent 的 `configDirectoryPath` 与 `skillsDirectoryPath`
- `Services/AgentFileBrowserService.swift`：负责根目录树扫描、隐藏文件显示、只读保护与文件操作约束
- `Services/ToolPreferencesStore.swift` / `Services/ApplicationLauncher.swift`：负责外置编辑器、默认终端偏好和实际启动行为
- `ViewModels/AgentFilesViewModel.swift`：负责 `Agent Files` 页面的加载、选择、文本预览、编辑态切换、未保存保护与系统跳转
- `ViewModels/TextFileEditorViewModel.swift`：负责纯文本编辑器的加载、保存与脏状态
- `ViewModels/TextFilePreviewViewModel.swift`：负责文本文件预览的加载、10 MB 降级和格式化后的展示内容
- `Views/AgentFiles/`、`Views/Components/TextFilePreviewView.swift` 与 `Views/Editor/TextFileEditorView.swift`：负责文件树、详情、只读预览和纯文本编辑 UI

当前 `Skill Detail` 存在两种展示模式：
- `Installed > All Skills` 进入时显示完整管理视图：Metadata、包信息、更新状态、Agent 分配与 Finder / Terminal / 编辑操作
- `Agents > Agents Skills > 具体 Agent` 进入时显示只读内容视图：仅保留标题、描述、Metadata 与 Markdown 正文，不展示包信息、Agent 分配或任何管理按钮

## 启动与刷新主流程
1. `SkillsMasterApp` 注入全局 `SkillManager`
2. `ContentView` 首次出现时执行迁移：`MigrationManager.migrateIfNeeded()`
3. 随后调用 `SkillManager.refresh()`
4. `refresh()` 负责加载仓库配置、检测已安装代理、扫描 Skills、关联 lock file、触发自定义仓库后台同步
5. `FileSystemWatcher` 监听目录变化，变更后再次触发 `refresh()`

## 数据与存储约定
当前实现使用以下本地路径：
- canonical 存储目录：`~/.skillsmaster/skills`
- lock file：`~/.agents/.skill-lock.json`
- 自定义仓库克隆目录：`~/.skillsmaster/repos`
- 自定义仓库配置：`~/.skillsmaster/.skillsmaster-repos.json`
- 提交哈希缓存：`~/.skillsmaster/.skillsmaster-cache.json`（迁移后私有缓存）
- 自定义仓库扫描缓存：`~/.skillsmaster/.repository-scan-cache.json`（按仓库 HEAD 复用轻量索引；working tree 有本地改动时跳过缓存）

其中需要特别注意：
- `~/.skillsmaster/skills` 是 SkillsMaster 自己维护的 canonical 目录，也是 managed skill 的事实源
- `~/.agents/.skill-lock.json` 仍保留在旧位置，以兼容外部工具
- 扫描阶段仍会兼容读取 `~/.agents/skills`，用于兼容旧数据以及部分 Agent 的附加读取规则
- 每个 Agent 可以单独配置默认 direct install 方式：`symbolic link` 或 `physical copy`

## 代理与兼容策略
`AgentType` 定义了当前受支持代理、检测命令、配置根目录、主技能目录与附加可读目录。不是所有代理都只读取自己的目录：
- Codex、Gemini CLI 仍兼容读取 `~/.agents/skills`
- OpenCode、Copilot、Cursor 等存在跨目录读取或继承关系
- SkillsMaster 在 UI 中区分“直接安装”和“继承安装”，避免误删或误切换
- Sidebar 的 `Agents` 分组先显示 `Agent Files`，再显示 `Agents Skills`
- `Agent Files` 的根目录以 `configDirectoryPath` 为准；例如 Codex 为 `~/.codex`，Claude Code 为 `~/.claude`
- 只有 CLI 已安装或配置目录已存在的 Agent，才会在 Sidebar 的 `Agents > Agent Files` 下显示
- `skills/` 目录及其子树在 `Agent Files` 中视为受保护路径：允许浏览、允许只读预览、允许 Finder / Terminal 跳转，但不允许新建、重命名、删除、内置编辑或外置编辑
- `Agent Files` 对 `.md`、`.json`、`.toml`、`.txt`、`.yaml`、`.yml`、`.log` 提供内置文本预览；其中 Markdown 走原生渲染，其他类型走等宽代码块展示，超过 10 MB 时统一回退为原始文本预览
- `Agent Files` 的内置编辑格式与上述预览格式保持一致；`SKILL.md` 在 `Skill Detail` 中也复用同一套纯文本编辑器，但不会绕过 `Agent Files` 的只读保护规则
- 外置编辑器是全局设置；默认终端也是全局设置，当前支持 Terminal / iTerm / Warp / Ghostty

处理代理相关问题时，应优先查看：
- `Sources/SkillsMaster/Models/AgentType.swift`
- `Sources/SkillsMaster/Services/SkillScanner.swift`
- `Sources/SkillsMaster/Services/SymlinkManager.swift`

## 仓库与安装链路
当前安装来源分为四类：
- 注册表技能：通过 `SkillRegistryService` 获取索引，并在详情页内联勾选 Agent 后执行安装
- ClawHub：通过 `ClawHubService` 拉取 marketplace 列表、详情、`SKILL.md` 与 archive，由 `ClawHubBrowserViewModel` 编排浏览/安装，并通过 `SkillManager.installClawHubSkill(...)` 安装到 canonical 目录后按目标 Agent 集合落盘；详细链路见 `docs/clawhub.md`
- SkillsHub：通过 `SkillsHubService` 拉取 SkillsHub 列表、精选、轻量搜索与 archive，由 `SkillsHubBrowserViewModel` 编排浏览/安装，并通过 `SkillManager.installSkillsHubSkill(...)` 安装到 canonical 目录后按目标 Agent 集合落盘；详细链路见 `docs/skillhub.md`
- 远程仓库安装：通过 `GitService` 克隆 / 扫描 / 拷贝到 canonical 目录
- 自定义仓库：由 `RepositoryManager` 管理配置、同步与轻量索引缓存，由 `RepositoryBrowserViewModel` 驱动浏览与安装；列表使用缓存索引，详情页按需加载完整 `SKILL.md`，并在详情页内联勾选 Agent 后执行安装。`~/.skillsmaster/repos` 下的 clone 目录视为 SkillsMaster 内部缓存，不作为用户手动编辑的工作目录；若检测到本地未提交改动，会跳过扫描缓存以避免展示过期索引。

统一安装后都会落到 canonical 目录，再按各 Agent 的默认安装方式把 direct install 落到代理目录，并由 `LockFileManager` 更新 lock file。Marketplace 与 Custom Repository 详情页默认不预选 Agent；空选择点击按钮会弹 alert；若已选 Agent 中同时包含“已直接安装”和“未直接安装”的目标，主按钮显示 `Install / Reinstall`。对于 physical copy，后续更新、重新安装和应用内编辑也会同步覆盖 Agent 目录副本。

## 更新链路
- 技能更新：Git 来源由 `GitService` + `CommitHashCache` 负责；SkillsHub 来源由 `SkillsHubService` 提供 version 与 archive 更新语义；ClawHub / local 当前不走统一更新检查
- 应用自更新：`UpdateChecker` 读取 GitHub Release，下载 zip 并替换当前 `.app`；若安装在 `/Applications` 等受保护目录，会先申请管理员权限，再由外部脚本在应用退出后完成替换与重启
- 应用自更新的前置限制：必须从真实 `.app` bundle 启动；若当前实例处于 App Translocation、DMG 或其他只读卷，更新器会先报错而不是静默失败
- 发布打包：`scripts/package-app.sh`、`scripts/release.sh`、`.github/workflows/release.yml`

## 高风险区域
以下区域文档、代码和测试必须同步：
- `MigrationManager.swift`：历史路径迁移与兼容
- `LockFileManager.swift`：lock file 格式与原子写入
- `SymlinkManager.swift`：symbolic link 创建、解析、删除与 direct install / 继承识别
- `RepositoryManager.swift` / `RepositoryCredentialStore.swift`：仓库配置与凭据存储
- `UpdateChecker.swift`：应用下载、替换、重启流程
- `scripts/` 与 `.github/workflows/`：打包与 GitHub Release 发布

## 文档边界
本文件只回答“系统如何工作、哪些路径和链路是权威实现”。
开发命令与提交规则见 `docs/development.md`；发布流程见 `docs/release.md`；能力边界见 `docs/roadmap.md`。
