# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-03-20
### Fixed
- 修复 ClawHub 浏览列表在当前站点协议下始终为空的问题。根因是 SkillsMaster 仍依赖旧的 `GET /api/v1/skills` 返回模型，而线上 ClawHub 已切换到 Convex public query。
- 修复 ClawHub 详情与 `SKILL.md` 加载链路对旧接口的依赖，改为对齐当前网站正在使用的详情查询与内容 action，避免详情面板加载失败或内容缺失。
- 修复 ClawHub 搜索链路与线上实现漂移的问题。主路径改为当前网站使用的搜索 action，同时保留旧 REST 搜索作为 fallback，降低上游再次变更时的回归风险。
- 修复 ClawHub browse 分页策略过时的问题。浏览模式改为使用服务端返回的 cursor 分页，而不是持续放大 `limit` 去重拉“前 N 条”。
