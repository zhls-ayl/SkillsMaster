# 开发工作流

## 本地环境
- macOS 14+
- Xcode 15+
- Swift 5.9+

推荐优先使用：
- `./run`：统一入口；无参数默认本地运行，也可转发 `test` / `build` / `package` / `release` / `clean`
- `./run test`：执行全部单元测试
- `./run test --filter <TestCase>`：执行最小相关测试

## 常用命令
```bash
./run
./run dev
./run build
./run build -c release
./run test
./run test --filter SkillMDParserTests
./run test --enable-code-coverage
./run clean
./run package --version 1.2.3 --zip
./run package --version 1.2.3 --arch arm64 --zip
./run package --version 1.2.3 --arch x86_64 --zip
./run package --version 1.2.3 --dmg
./run package --version 1.2.3 --release-assets
```

## 本地构建与沙箱 / 提权排查
- 优先使用 `./run` 作为统一入口；根目录 `run` 会先把 `CLANG_MODULE_CACHE_PATH` 与 `SWIFTPM_MODULECACHE_OVERRIDE` 固定到仓库内的 `.build/`，再分发到对应子命令，尽量减少项目路径变更带来的模块缓存问题
- `./run dev` 最终调用 `scripts/run.sh`，保留其“检测旧模块缓存后自动清理 `.build` 并重试一次”的行为
- 直接执行 `swift build`、`swift run`、`swift test` 前，应先预判 AI 所在环境是否存在沙箱限制；若大概率会访问系统 Swift / clang cache 目录，就应优先准备提权，而不是等失败后再判断
- 若任务需要直接执行这些命令，且已知当前环境常因系统缓存/权限受限而失败，应在执行前就向用户说明并申请提权；出现 `Operation not permitted`、`ModuleCache`、`org.swift.swiftpm`、`unable to load standard library`、manifest 无法编译等信号时，更应立即按环境限制处理
- 获得提权后，优先重跑原始命令确认真实编译结果；只有在提权后仍失败，才继续定位代码、配置或依赖问题
- 如果是项目路径迁移后触发的模块缓存不一致，优先重试 `./run` 或 `./run dev`；该入口会继续复用 `scripts/run.sh` 的自动重试逻辑
- 将这类经验同步沉淀为后续任务的前置检查：协作与提权规则写入 `AGENTS.md`，开发实操中的预检与入口选择写入本文件

## 开始前预检
- 在执行本地构建、运行、测试、发布脚本前，先看一遍当前任务相关的环境约束与已知易错点，不要等失败后再回头补查
- 需要直接跑 `swift build`、`swift run`、`swift test` 时，先判断当前环境是否可能受沙箱限制；若 AI 运行环境受限，优先预判是否需要先申请提权
- 需要本地运行应用时，默认优先使用 `./run` 或 `./run dev`，不要把它当成构建失败后的兜底方案；它本身就是用于规避模块缓存与路径迁移问题的首选入口
- 需要本地测试、构建、打包时，也优先从 `./run test`、`./run build`、`./run package` 进入，统一环境准备和命令入口
- 遇到历史上已经确认过的高频问题，应先把对应预防动作纳入本次操作步骤，例如先选对入口命令、先检查权限边界、先确认路径与缓存策略

## 开发流程
1. 先确认需求、范围、风险点与交付物
2. 阅读相关 `Service` / `ViewModel` / `View` / `Tests`
3. 判断是否涉及路径、迁移、lock file、仓库同步、Release 脚本等高风险区域
4. 做最小可验证变更（minimal change）
5. 补充或更新相邻测试用例
6. 更新对应文档
7. 最后检查 README、docs 与代码命名是否一致

## 代码约束
- `Views/` 只放展示和轻交互，不承载底层文件系统或 Git 逻辑
- `ViewModels/` 负责编排，不复制 `Service` 中的核心规则
- `Services/` 优先保持单一职责；跨多个能力的调度收敛到 `SkillManager`
- 新增路径、存储文件、配置项时，优先落在 `Utilities/Constants.swift`
- 不把临时调试逻辑、一次性脚本说明写进长期文档

## 测试要求
- 代码改动默认要补测试，尤其是：
  - 代理目录规则
  - lock file 读写
  - symbolic link 判断
  - Git URL 解析与仓库扫描
  - Markdown / `SKILL.md` 解析
  - ViewModel 的状态转换
- 优先跑最小相关测试，再根据影响范围决定是否运行 `swift test`
- 不为未改动的旧问题顺手扩散修复；如发现，应单独说明

## 文档更新要求
以下改动必须同步文档：
- 修改用户可见行为：更新 `README.md` 或 `docs/roadmap.md`
- 修改实现结构、路径或迁移逻辑：更新 `docs/architecture.md`
- 修改命令、测试方法、开发流程，尤其是 `./run` 支持的统一入口与参数：更新本文件
- 修改打包、发布、GitHub Actions、Homebrew：更新 `docs/release.md`

## 提交与 Review 约定
当前提交历史采用 Conventional Commits：
- `feat(...)`
- `fix(...)`
- `refactor(...)`
- `build(...)`
- `docs`

建议提交前自查：
- 代码是否有相邻测试用例支撑
- 文档是否仍然指向真实文件和真实命令
- 是否引入了新的路径分叉、配置漂移或未记录的行为变化
