# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
