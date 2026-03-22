# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
