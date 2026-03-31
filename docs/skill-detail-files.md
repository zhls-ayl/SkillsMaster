# Skill Detail 多文件浏览设计与实现规格

## 文档状态
- 状态：Design Spec + Implementation Notes
- 实现状态：已落地（首版）
- 适用范围：`Installed > All Skills > Skill Detail` 以及 `Agents > Agents Skills > Skill Detail`
- 目标：为当前以 `SKILL.md` 为中心的详情页，补充同一 Skill 文件夹内其他文件的发现、浏览、预览与有限编辑能力

## 背景与当前事实
当前仓库中的 Skill 详情页由 `Sources/SkillsMaster/Views/Detail/SkillDetailView.swift` 渲染，核心焦点是：
- Skill 标题、描述与 Metadata
- lock file / repository / update / Agent assignment
- `SKILL.md` Markdown 正文

当前应用已经具备一套成熟的文件树、文本预览与纯文本编辑能力，但挂载在 `Agent Files` 语境中，而不是 Skill 详情语境中。相关实现主要位于：
- `Sources/SkillsMaster/Services/AgentFileBrowserService.swift`
- `Sources/SkillsMaster/ViewModels/AgentFilesViewModel.swift`
- `Sources/SkillsMaster/Views/AgentFiles/AgentFilesBrowserView.swift`
- `Sources/SkillsMaster/Views/AgentFiles/AgentFileDetailView.swift`
- `Sources/SkillsMaster/Views/Components/TextFilePreviewView.swift`
- `Sources/SkillsMaster/Views/Editor/TextFileEditorView.swift`

当前事实与问题如下：
- 每个 Skill 在底层物理结构上对应一个独立文件夹
- Skill 详情页目前默认只展示该文件夹内的 `SKILL.md`
- 用户无法在 Skill 详情页中直接感知同级或下级文件
- 当 Skill 含有脚本、配置、媒体资源、补充文档或子目录时，用户会进入“信息盲区”
- 现有 `Agent Files` 能看见文件，但它是以 Agent root 为上下文，不是以“当前 Skill”作为阅读与操作上下文

本规格的目标不是把 Skill 详情页重做成通用文件管理器，而是在不削弱 `SKILL.md` 主入口地位的前提下，引入 Skill-scoped 的多文件上下文。

## 设计目标
- 保持 `SKILL.md` 仍是 Skill 详情的默认首页与视觉焦点
- 让用户明确知道当前 Skill 目录中还有哪些关联文件
- 在需要时提供无缝的文件发现、预览、定位与有限编辑能力
- 在查看其他文件时，持续保留“我仍在当前 Skill 内”的上下文锚点
- 兼容两种极端：
  - 只有 2 到 3 个文件的轻量 Skill
  - 含几十个文件与多级嵌套目录的复杂 Skill

## 非目标
- 不把 Skill 详情页升级为完整 IDE 或通用文件管理器
- 不在首次进入 Skill 详情时直接展示全量文件树
- 不让 `SKILL.md` 与其他文件成为并列一级入口
- 不在本次方案中覆盖高级编辑能力，如 syntax highlighting、diff-aware 编辑、LSP
- 不在本次方案中定义全局文件搜索，只定义当前 Skill 范围内的局部搜索
- 不破坏 `contentOnly` 入口原有的只读语义；`Agents > Agents Skills` 下允许浏览关联文件，但不应重新暴露管理按钮

## 核心用户动机
用户查看 `SKILL.md` 之外其他文件的动机通常集中在以下 4 类：

### 1. 阅读
- 查看补充文档、使用说明、示例输出、迁移说明
- 阅读脚本头部注释、配置模板、局部 README

### 2. 理解结构
- 确认这个 Skill 实际包含哪些脚本、配置与资源
- 判断 `SKILL.md` 中提到的命令、入口文件或依赖文件是否真实存在

### 3. 引用与复制
- 复制文件路径、配置片段、命令参数或脚本内容
- 对照 `SKILL.md` 与实际文件内容

### 4. 编辑与排错
- 修改 `.json`、`.toml`、`.yaml`、`.md`、`.txt` 等受支持文本文件
- 检查某个脚本、配置或附属文档导致的问题

优先级排序应为：
- 阅读与理解结构
- 引用与复制
- 编辑与排错

这意味着该方案默认应是 read-first，而不是 edit-first。

## 信息架构与命名
### 核心对象
- `Skill Home`：当前 Skill 的 `SKILL.md`
- `Related Files`：当前 Skill 文件夹内，除 `SKILL.md` 以外的同级或下级文件与目录
- `Current File`：用户当前正在查看的附属文件

### 推荐命名
- 入口按钮：`Related Files`
- 抽屉标题：`Files in this Skill`
- 主页锚点：`Back to SKILL.md`
- 根节点：`Home`

### IA 原则
- `SKILL.md` 永远是默认首页
- “其他文件”属于当前 Skill 的上下文补充，而不是新的一级导航
- 文件浏览必须被包裹在当前 Skill 语境中，不允许用户误以为自己进入了全局文件系统

## 方案结论
推荐采用：`Contextual Files Drawer`

方案定义：
- 默认仍显示现有 `Skill Detail`
- 只有检测到额外文件时，才提供 `Related Files` 入口
- 点击后，从 detail pane 右侧滑出一个 Skill-scoped 文件抽屉
- 抽屉负责文件发现与切换
- 主内容区负责 `SKILL.md`、文件预览、不可预览占位与文本编辑

不推荐直接采用 `Overview / Files` 双主视图或 Tab 并列方案，原因如下：
- 会削弱 `SKILL.md` 的主页地位
- 对轻量 Skill 过重
- 容易把详情页演化为文件管理器，而不是 Skill 详情

## 布局结构
本方案基于当前 `NavigationSplitView` 三栏结构，不新增全局导航层。

### 默认态
- 左栏：Sidebar
- 中栏：Skill 列表
- 右栏：Skill Detail

### 引入文件抽屉后的 detail 结构
- 主内容区：继续承载 `Skill Detail` 的正文
- 右侧抽屉：承载当前 Skill 的文件树与局部搜索

视觉层级要求：
- `SKILL.md` 正文区域仍是默认第一视觉焦点
- 抽屉是 secondary region，不应压过正文
- 文件预览态也必须保留 Skill 标题与 breadcrumb，不能退化为“只看文件名”

## 渐进式呈现规则
### 是否显示入口
- 额外文件数 `= 0`：不显示 `Related Files`
- 正在扫描目录：显示一个低强调 loading 态，不抢占正文
- 额外文件数 `> 0`：显示 `Related Files (n)`

### 文件规模分层
- 额外文件数 `1~5`：
  - 抽屉内默认平铺列表
  - 不显示搜索框
- 额外文件数 `6~20` 或存在子目录：
  - 使用树形列表
  - 支持展开与收起
- 额外文件数 `> 20` 或目录层级 `>= 3`：
  - 抽屉顶部显示搜索框
  - 支持按文件名与相对路径过滤

### 排序与过滤
- 固定顺序：`SKILL.md` > 文件夹 > 文件
- `SKILL.md` 作为固定 `Home` 节点，不参与计数 badge
- 文件夹和文件各自按名称排序
- 系统噪音文件如 `.DS_Store` 默认隐藏
- 隐藏文件默认不显示；若未来支持，也必须放入显式 reveal 机制，而不是默认暴露

## 核心用户流
### Flow 1：默认阅读 `SKILL.md`
1. 用户在中栏选择一个 Skill
2. 右栏默认渲染现有 Skill 详情
3. 系统后台扫描 Skill 根目录
4. 若发现额外文件，在标题区或 toolbar 显示 `Related Files (n)`

### Flow 2：打开相关文件抽屉
1. 用户点击 `Related Files`
2. 抽屉从右侧滑出
3. 抽屉顶部显示：
   - 当前 Skill 名称
   - 相对根路径摘要
   - 可选搜索框
4. 抽屉第一项固定显示：
   - `Home`
   - `SKILL.md`
5. 下方展示文件树或文件列表

### Flow 3：查看可预览文件
1. 用户在抽屉中点选某个文本文件
2. 主内容区从 `Home` 切换到 `File Preview`
3. 顶部显示：
   - `Skill Name / relative/path/to/file`
   - `Back to SKILL.md`
   - 对应动作按钮
4. 主体展示该文件内容

### Flow 4：编辑文本文件
1. 用户在文件预览态点击 `Edit`
2. 主内容区进入编辑态
3. 若切换文件、关闭抽屉或返回 `SKILL.md` 时存在未保存修改：
   - 复用现有 unsaved changes 交互
   - 不定义第二套确认机制

### Flow 5：返回 `SKILL.md`
用户可以通过以下任一方式回到主页：
- 点击顶部 `Back to SKILL.md`
- 点击抽屉中的 `Home`
- 关闭抽屉后保留 Home 视图

## 界面状态
### 主内容区状态
- `Home`
  - 展示原有 `SKILL.md` 详情页
- `File Preview`
  - 展示可内置预览的文本文件
- `File Editor`
  - 展示纯文本编辑器
- `Unsupported Preview`
  - 展示不可预览文件的占位卡片
- `Missing File`
  - 当前文件已被外部删除
- `Read Error`
  - 文件读取失败或编码异常

### 抽屉状态
- `Hidden`
- `Loading`
- `Ready`
- `Search Filtering`
- `Empty but Available`
  - 理论上不应出现；若索引结果异常，应转为错误态而不是空态
- `Index Error`

### 全局辅助状态
- `File changed externally`
- `Unsaved Changes`
- `Loading details...`

## 组件清单
建议组件拆分如下：

### Detail 容器层
- `SkillDetailView`
  - 继续作为 Skill 详情根视图
  - 持有 `SkillRelatedFilesButton`
  - 在正文区挂载 `SkillFileContentSwitcher`
  - 在 trailing 区域挂载 `SkillRelatedFilesDrawer`

### 文件抽屉层
- `SkillRelatedFilesButton`
  - 显示入口、badge、loading
- `SkillRelatedFilesDrawer`
  - 承载文件树、搜索、Home 节点
- `SkillFileTreeView`
  - 负责目录树、展开状态与行渲染
- `SkillFileTreeRow`
  - 负责目录/文件单行显示
- `SkillFileSearchField`
  - 大目录下的局部搜索

### 文件内容层
- `SkillFileContextBar`
  - 显示 Skill 名称、当前路径、返回锚点
- `SkillFileContentSwitcher`
  - 根据当前状态切换主内容区
- `SkillUnsupportedPreviewCard`
  - 处理二进制或不支持预览的文件
- `SkillMissingFileView`
  - 处理外部删除

### 复用组件
以下能力应尽可能复用现有实现：
- 文本预览：`TextFilePreviewView`
- 文本编辑：`TextFileEditorView`
- 文件详情元信息：可复用 `AgentFileDetailView` 中的部分布局与文案

## ViewModel 建议
不建议把 Skill 详情与多文件浏览状态全部塞入现有 `SkillDetailViewModel`。建议增加子域 `SkillRelatedFilesViewModel`，由 `SkillDetailViewModel` 持有。

### 建议状态模型
```swift
enum SkillDetailContentTarget: Equatable {
    case home
    case file(URL)
    case unsupported(URL)
    case missing(URL)
}
```

### `SkillRelatedFilesViewModel` 建议字段
- `let skillRootURL: URL`
- `let skillMDURL: URL`
- `var isIndexLoading = false`
- `var indexError: String?`
- `var isDrawerPresented = false`
- `var entries: [AgentFileItem] = []`
- `var selectedItemID: String?`
- `var selectedTarget: SkillDetailContentTarget = .home`
- `var expandedDirectoryIDs = Set<String>()`
- `var loadingDirectoryIDs = Set<String>()`
- `var searchQuery = ""`
- `var selectedItemDetails: AgentFileDetails?`
- `var previewViewModel: TextFilePreviewViewModel?`
- `var editorViewModel: TextFileEditorViewModel?`
- `var pendingNavigationAction: PendingNavigationAction?`
- `var externalChangeMessage: String?`

### 派生状态
- `hasRelatedFiles`
- `extraFileCount`
- `shouldShowSearch`
- `isHomeSelected`
- `currentRelativePath`
- `canEditSelectedFile`
- `canPreviewSelectedFile`

### 建议接口
- `loadIndexIfNeeded()`
- `toggleDrawer()`
- `selectHome()`
- `requestSelectionChange(to:)`
- `toggleExpansion(for:)`
- `loadSelectedItemDetails()`
- `prepareSelectedItemPreview()`
- `startEditingSelectedFile()`
- `requestCloseEditor()`
- `saveCurrentEditorAndClose()`
- `reloadSelectedFile()`
- `handleExternalMutation()`
- `resetForSkillChange()`

## Service 设计建议
### 原则
- 尽量复用当前文件树扫描、文件详情读取、文本文件判断逻辑
- 不直接复用 `Agent Files` 的只读保护语义
- Skill 文件浏览是 Skill-scoped，不是 Agent root-scoped

### 建议方向
可以从 `AgentFileBrowserService` 中抽出与“目录索引 / 文件详情 / 文本文件判断”相关的共用能力，再建立更轻量的 `SkillFileBrowserService`。

### `SkillFileBrowserService` 建议职责
- 扫描当前 Skill 根目录
- 构建文件树
- 过滤 `SKILL.md` 之外的文件
- 读取文件详情
- 判断文件是否支持内置预览
- 提供隐藏文件过滤策略
- 提供目录变更监听的 watch 范围

## 交互细节要求
### 入口
- 建议放在标题区右侧或 toolbar
- 样式应低于主操作按钮
- badge 只统计 `SKILL.md` 之外的可见文件与目录

### 抽屉
- 建议宽度：`280-320 pt`
- 打开动画：短距离 slide-in
- 建议时长：`160-200 ms`
- 不应覆盖整个 detail 内容；应保留主内容区可读性

### 上下文锚点
只要用户不在 Home 态，就必须显示：
- 当前 Skill 名称
- 当前文件相对路径
- 明确的返回 `SKILL.md` 入口

### 文件预览
- Markdown 使用原生渲染
- `.json`、`.toml`、`.yaml`、`.txt`、`.log` 使用等宽文本卡片
- 超过既有大文件阈值时，沿用当前原始文本降级策略

### 编辑
- 仅对受支持文本文件显示 `Edit`
- 保持现有纯文本编辑器体验
- 未保存修改保护沿用现有逻辑

## Edge Cases 与异常处理
### 只有 `SKILL.md`
- 不显示 `Related Files`
- 可选地在细节区显示一条低强调说明：
  - `This Skill contains only SKILL.md.`
- 不应出现空抽屉或不可点击的占位入口

### 不支持预览的文件
文件仍应出现在文件树中，但主内容区显示 `Unsupported Preview Card`，至少包含：
- 文件名
- 类型
- 大小
- 修改时间
- `Show in Finder`
- `Open with Default App`

如果文件可能具有执行风险，默认强调 `Show in Finder`，不要把“直接打开”作为唯一主动作。

### 外部修改
- 若当前预览文件被外部修改，应显示轻量提示：
  - `File changed externally`
- 提供 `Reload`

### 外部删除
- 若当前文件被外部删除，主内容区进入 `Missing File`
- 顶部上下文栏与 `Back to SKILL.md` 仍应保留

### 目录很大
- 启用搜索
- 记忆目录展开状态
- 仅在当前 Skill 作用域内过滤与展示

### 长路径
- 抽屉内文本截断
- hover 提示完整路径
- 主内容区上下文栏可复制完整相对路径

### Symbolic link
- 默认展示 link 本身
- 不递归展开其目标目录，除非后续实现明确支持并评估风险

## 验收标准
以下标准用于后续开发验收：
- 默认进入 Skill 详情时，`SKILL.md` 仍是第一视图
- 除 `SKILL.md` 外无其他文件时，UI 无死入口、无噪音空态
- 用户查看任何附属文件时，始终知道自己仍处于当前 Skill 内
- 任意时刻都可以一键返回 `SKILL.md`
- 不支持预览的文件不会导致空白页
- 文本文件的预览与编辑复用现有能力，不引入第二套编辑器语义
- 大目录下的文件树仍可用，搜索与展开不会破坏上下文
- 未保存修改切换时沿用现有确认机制
- `contentOnly` 入口在支持关联文件浏览后，仍必须保持“无管理按钮”的只读语义

## 分阶段实现建议
### Phase 1：可见性与只读浏览
- 建立 Skill-scoped 文件索引
- 在 `Skill Detail` 中显示 `Related Files`
- 支持抽屉、文件树、Home 节点
- 支持文本预览与不可预览占位

### Phase 2：文本编辑
- 复用现有文本编辑器
- 接入 unsaved changes 保护
- 接入外部变化监听与 reload

### Phase 3：大目录优化
- 引入搜索
- 优化展开状态记忆
- 优化大目录与多层嵌套时的性能与可读性

## 文档维护规则
当该方案进入开发或落地后，至少同步检查并更新以下文档：
- `docs/architecture.md`
- `docs/roadmap.md`
- `README.md`
- `README_CN.md`
- 本文档 `docs/skill-detail-files.md`

如果最终实现显著偏离本文档，应优先更新本文档，再更新对外说明，避免再次出现“文档说有、实现没有”或“实现有、文档没跟上”的情况。
