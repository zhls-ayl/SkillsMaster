# 文档索引

本文件只负责 **文档导航与文档维护规则**，不重复 `README.md` 的项目介绍，也不承担 `AGENTS.md` 的协作执行规则。

## 三份入口文档的职责边界
- `README.md`：项目概览、适用人群、快速开始、界面预览
- `docs/Index.md`：详细文档导航、阅读顺序、文档更新落点
- `AGENTS.md`：仓库协作原则、决策边界、验证要求、高风险改动规则

## 建议阅读顺序
- 想快速了解项目：英文读者先读 `README.md`，中文读者先读 `README_CN.md`
- 想继续理解实现与专题文档：再读 `docs/architecture.md`
- 想理解 ClawHub 浏览、详情与安装链路：补读 `docs/clawhub.md`
- 想理解 SkillsHub 浏览、archive 详情、安装与更新链路：补读 `docs/skillhub.md`
- 想参与开发或验证改动：继续读 `docs/development.md`
- 涉及打包、发布、Homebrew、自更新：再读 `docs/release.md`
- 想确认能力边界与未实现项：补读 `docs/roadmap.md`

## 文档更新落点
- 改项目定位、使用方式、入口说明、截图结构：同步更新 `README.md` 与 `README_CN.md`
- 改文档目录、阅读顺序、文档维护规则：更新 `docs/Index.md`
- 改模块职责、路径约定、扫描/同步/迁移逻辑、存储结构：更新 `docs/architecture.md`
- 改 ClawHub 入口、模型、API 对接、分页、详情加载、安装落盘与限制条件：更新 `docs/clawhub.md`
- 改 SkillsHub 入口、模型、浏览接口、archive 详情、安装落盘与更新语义：更新 `docs/skillhub.md`
- 改本地开发方式、测试方法、工程约束、协作流程：更新 `docs/development.md`
- 改脚本、发布流程、产物命名、版本策略、分发方式：更新 `docs/release.md`
- 改能力范围、已交付能力、明确未实现项：更新 `docs/roadmap.md`
- 对话中新增的经验也按同样规则归档，并优先改写成“执行前提示”而非“事后补救”：协作/提权/验证类写 `AGENTS.md`，面向用户的使用风险提示写 `README.md`，文档维护导航与执行前阅读建议写 `docs/Index.md`，专题实现的预检与预防步骤写到对应专题文档

## 当前目录说明
- `docs/screenshots/`：文档插图资源
- `docs/clawhub.md`：ClawHub 浏览、详情与安装链路专题
- `docs/skillhub.md`：SkillsHub 浏览、archive 详情、安装与更新链路专题
- 其余 Markdown 文件按主题平铺，避免深层目录导致检索成本升高

## 维护要求
- 文档描述必须以代码、测试、脚本、workflow 为准
- 如果一个信息已经由 `README.md` 或专题文档权威维护，就不要在这里重复展开
- 如果一个改动影响多个专题，必须同步更新全部相关文档，而不是只改入口说明
