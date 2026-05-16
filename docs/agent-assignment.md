# Agent 分配（Agent Assignment）

本文档面向 `Skill Detail` 中 `Agent Assignments` 区域的实现维护者，说明厂家分组定义、批量操作语义、UI 行为与 canonical 路径保护机制。改动相关代码或交互前请先核对本文，并在变更后同步本文。

## 设计目标
- 用厂家分组替代过去的平铺列表，让支持的 Agent 数量持续增长时仍易于定位
- 提供分组级和全局级的 `Select All` / `Remove All`，降低多 Agent 操作的重复点击
- 批量操作不能丢失 skill 数据；当 canonical 路径恰好位于某 Agent 自身目录时，必须先迁移再删除
- 批量循环不能因为高频 refresh 触发并发 git 进程而崩溃

## 分组定义
分组与 Agent 的归属定义在 `Sources/SkillsMaster/Models/AgentGroup.swift`。当前分组顺序与归属：

| 分组 | 显示名 | 包含 Agent |
|------|--------|------------|
| `.anthropic` | Anthropic | `claudeCode` |
| `.openAI` | OpenAI | `codex` |
| `.google` | Google | `geminiCLI`, `antigravity` |
| `.gitHub` | GitHub | `githubCopilot` |
| `.cursor` | Cursor | `cursor` |
| `.aws` | AWS | `kiroCLI` |
| `.tencent` | Tencent | `codeBuddy`, `workBuddy` |
| `.byteDance` | ByteDance | `trae`, `traeCN` |
| `.independent` | Independent | `openCode`, `openClaw` |

约束：
- 每个 `AgentType` 必须恰好属于一个分组；`AgentGroup.agents` 与 `AgentGroup.group(for:)` 都使用 exhaustive switch，新增 `AgentType` case 时编译期会强制要求补齐分组归属
- 分组顺序由 `rawValue` 升序决定，不随运行时状态变化
- 分组内 Agent 顺序由 `sortedAgents` 决定：先按 `displayName` 字符数升序，再按 `localizedStandardCompare` 升序

`Trae` 与 `Trae CN` 共享同一 SVG 资源（`Resources/AgentIcons/trae.svg`），区分仅在 `displayName`、`configDirectoryPath`（`~/.trae` vs `~/.trae-cn`）、`skillsDirectoryPath` 上。

## UI 实现
入口视图：`Sources/SkillsMaster/Views/Components/AgentToggleView.swift`，由 `Views/Detail/SkillDetailView.swift` 的 `agentAssignmentSection` 调用。Marketplace 与 Repository 详情页中的 Agent 选择器（`Views/Components/MarketplaceInstallTargetsView.swift`）也按同一分组规则渲染。

每个 Agent 行采用卡片样式：
- 圆角背景 + 边框；激活时使用 accent color 高亮（背景 12% 不透明度，边框 50% 不透明度）
- 状态指示用 `checkmark.circle.fill` / `circle`，整行可点击切换
- `isOn` 直接从 `skillManager.skills` 派生（不缓存到 `@State`），保证批量操作后 UI 立即反映最新状态

分组标题旁的按钮：
- `Select All`：分组内存在至少一个未直接安装的 Agent 时启用；点击调用 `viewModel.selectAllAgents(in:for:)`
- `Remove All`：分组内存在至少一个已直接安装的 Agent 时启用；点击调用 `viewModel.removeAllAgents(in:for:)`，使用红色 tint 表示破坏性操作

区域顶部还提供全局 `Select All` / `Remove All`：
- 行为等同于遍历所有 `AgentType` 而非递归调用各分组方法
- 操作期间禁用按钮，并在标题旁展示 `ProgressView`

批量行为放宽：
- `Select All` 不再过滤"未安装的 Agent"，会主动为它们创建 skills 目录并落盘，方便用户提前为未来安装的 Agent 准备 skill
- 单行点击同样允许对未安装 Agent 操作，与批量行为保持一致

## ViewModel 与 SkillManager 协作
`SkillDetailViewModel` 暴露三个状态属性：
- `batchOperatingGroups: Set<AgentGroup>`：当前正在执行批量操作的分组集合（用于 disable 对应 UI）
- `isGlobalBatchOperating: Bool`：全局操作是否在执行
- `batchErrors: [String]`：上一次批量操作中失败 Agent 的 displayName 列表

批量循环用 `SkillManager.toggleAssignmentWithoutRefresh(_:agent:)` 同步执行，循环结束后只调用一次 `refresh()`。`assignSkillWithoutRefresh` / `unassignSkillWithoutRefresh` 是配套的"不刷新"变体；外部业务（`SkillDetailViewModel.toggleAgent` 单条操作）仍走 `assignSkill` / `unassignSkill`，由它们各自负责 refresh。

## Canonical 路径保护
当 skill 的 `canonicalURL` 恰好位于某 Agent 自身的 `skillsDirectoryURL` 下（例如 skill 最早安装在 `~/.workbuddy/skills/find-skills`，没有显式迁移到 `~/.skillsmaster/skills/`），直接 `removeDirectInstall` 会同时删除事实源，导致 skill 消失，其他 Agent 的 symlink 变成悬空。

`SkillManager.unassignSkill` 在执行删除前先做检测：

```
agentTargetURL == skill.canonicalURL ?
  → promoteCanonicalToPrivateDirectory(skill, currentlyAt:)
    1. 在 ~/.skillsmaster/skills/ 下复制一份作为新 canonical
    2. 把所有指向旧路径的 symlink 重新指向新位置
  → removeDirectInstall(skillName: skill.id, from: agent)
```

物理拷贝（`isSymlink == false`）的 direct install 在 promote 时不重链接，因为它本身已经是独立文件。整个流程使用 `try fm.copyItem`（不是 move），确保 `removeDirectInstall` 之前数据已经完整复制到新位置。

## 并发安全
批量循环里每次 `toggleAssignment` 都触发 `refresh`，refresh 又把 `syncAllRepositories` 作为后台 Task 启动。早期实现下，多次连续 refresh 会让多个 sync task 并发跑，多个 git 子进程同时存在，pipe 文件描述符冲突，`readDataToEndOfFile` 抛 ObjC 异常导致 app 崩溃。

当前防护：
- 批量循环用 `toggleAssignmentWithoutRefresh`，结束才 refresh 一次
- `SkillManager.syncAllRepositories` 增加 `isSyncingAllRepositories` 重入保护，已经在跑时直接返回
- `GitService.runGitCommand` 改用 `availableData` 循环读取 stdout/stderr，避开 `readDataToEndOfFile` 在并发场景下的 `NSFileHandle` 异常路径

## 验收要点
改动相关代码后，至少需要回归以下场景：
- 把 skill 的 canonical 放在某 Agent 目录下（`~/.workbuddy/skills/<id>`），点击该 Agent 的 Toggle 移除：skill 不应消失，应迁移到 `~/.skillsmaster/skills/`
- 同上场景下，点击该分组的 `Remove All`：行为应与单条移除一致
- 反复点击 `Select All` / `Remove All` 多次：app 不应崩溃，UI 状态应实时反映
- 新增 `AgentType` case：必须在 `AgentGroup.agents` 与 `AgentGroup.group(for:)` 中补齐，否则编译失败

## 测试覆盖
- `Tests/SkillsMasterTests/AgentGroupTests.swift`：分组归属唯一性、组内排序、分组元数据完整性
- `Tests/SkillsMasterTests/SkillDetailViewModelBatchTests.swift`：批量操作的容错性、状态管理、批量错误收集
- `Tests/SkillsMasterTests/AgentTypeTests.swift`：包括 `traeCN` 各项属性的单测

## 相关文件清单
- `Sources/SkillsMaster/Models/AgentGroup.swift`：分组定义
- `Sources/SkillsMaster/Models/AgentType.swift`：Agent 与分组归属
- `Sources/SkillsMaster/ViewModels/SkillDetailViewModel.swift`：批量操作方法与状态
- `Sources/SkillsMaster/Views/Components/AgentToggleView.swift`：分组渲染与卡片式 Agent 行
- `Sources/SkillsMaster/Views/Components/MarketplaceInstallTargetsView.swift`：Marketplace / Repository 详情中的同款分组
- `Sources/SkillsMaster/Views/Detail/SkillDetailView.swift`：`agentAssignmentSection` 中的全局 `Select All` / `Remove All`
- `Sources/SkillsMaster/Services/SkillManager.swift`：`toggleAssignmentWithoutRefresh`、`unassignSkill` 中的 canonical 保护、`syncAllRepositories` 重入保护
- `Sources/SkillsMaster/Services/GitService.swift`：`runGitCommand` 的 `availableData` 读取路径
