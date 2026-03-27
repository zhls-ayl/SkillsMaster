# 打包与发布（Release）

## 本地打包脚本
仓库当前使用以下脚本维护发布链路：
- `run`：统一命令入口；负责环境准备，并分发到开发、测试、构建、打包、发布子命令
- `scripts/package-app.sh`：构建 universal / arm64 / x86_64 `.app`，并按需生成 zip / dmg 或整套 release 产物
- `scripts/release.sh`：校验工作区、版本号、远端同步状态，并创建 / 推送 tag
- `scripts/run.sh`：本地运行入口，处理模块缓存与工具链异常提示
- `CHANGELOG.md`：发布记录与已修复缺陷入口；每次准备发布版本时都应同步更新

## 标准本地发布流程
```bash
./run test
./run package --version 1.2.3 --release-assets
./run release v1.2.3
```

其中：
- `run` 会先固定 Swift / clang module cache 到仓库内 `.build/`，再分发到对应子命令
- `package-app.sh` 会检查 `xcode-select`、`actool`、二进制架构与资源包，并可一次性产出整个 release matrix
- `release.sh` 要求工作区干净、目标分支已同步到将要触发 GitHub Release 的 remote、目标 tag 在本地与该 remote 上都不存在
- `CHANGELOG.md` 应至少包含该版本的 `Added` / `Changed` / `Fixed` 中实际发生的内容；若本次发布以修复缺陷为主，应优先记录缺陷现象与修复范围

多 remote 场景下，`release.sh` 会优先自动选择当前仓库里唯一的 GitHub remote。若存在多个 GitHub remote，必须显式指定：

```bash
./run release v1.2.3 --remote zhls-ayl
```

若在自动化环境中发布（或不希望交互确认），可以追加 `--yes` 进入 non-interactive 模式：

```bash
./run release v1.2.3 --remote zhls-ayl --yes
```

需要特别注意：
- GitHub 的 `Tags` 列表本身不直接承载安装包；实际下载的是该 tag 关联的 GitHub Release 附件
- 如果 `origin` 指向内部镜像、代码托管或其他非 GitHub 远端，必须确认 Release tag 被推送到真正触发 GitHub Actions 的 GitHub remote

## 常见本地打包命令
```bash
./run package --version 1.2.3 --zip
./run package --version 1.2.3 --arch arm64 --zip
./run package --version 1.2.3 --arch x86_64 --zip
./run package --version 1.2.3 --dmg
./run package --version 1.2.3 --release-assets
```

说明：
- 默认 `./run package --version ...` 构建 universal `.app`
- `--zip` 会为当前 `--arch` 产出对应 zip；未显式指定 `--arch` 时默认是 `universal.zip`
- `--dmg` 当前只支持 universal `.app`
- `--release-assets` 会一次性生成 release 需要的全部附件，不应再与 `--zip`、`--dmg` 或单架构 `--arch` 组合

## 统一入口与底层脚本的关系
- 推荐人工操作优先使用 `./run`
- `./run package ...` 最终调用 `scripts/package-app.sh`
- `./run release ...` 最终调用 `scripts/release.sh`
- `./run dev` 或无参数调用时，最终调用 `scripts/run.sh`
- CI、GitHub Actions、单独排查脚本问题时，仍可直接调用 `scripts/*.sh`
- `scripts/release.sh` 支持 `--remote <name>`，也支持通过 `RELEASE_REMOTE=<name>` 显式指定发布目标 remote
- `scripts/release.sh` 支持 `--yes`，用于跳过“非 main/master 分支确认”与“推送 tag 前确认”两个交互步骤

## GitHub Actions
- `.github/workflows/ci.yml`
  - 在 `push main` 和 `pull_request` 时执行 `swift build` 与 `swift test`
- `.github/workflows/release.yml`
  - 在推送 `v*` tag 时执行测试、构建 release matrix、创建 GitHub Release
  - 当前只负责 GitHub Release 产物，不再联动 Homebrew tap
  - workflow 文件内显式声明 `permissions: contents: write`，用于创建 Release；当前不需要把仓库默认 `Workflow permissions` 提升为全局 write

## 发布产物
当前发布产物命名为：
- `SkillsMaster.app`
- `SkillsMaster-v<version>-universal.zip`
- `SkillsMaster-v<version>-arm64.zip`
- `SkillsMaster-v<version>-x86_64.zip`
- `SkillsMaster-v<version>-universal.dmg`

用户从 GitHub 下载时，实际访问的是对应 Release 的附件；`Tags` 页只是该版本的入口之一。

其中需要特别注意：
- 应用内自更新仍以 `universal.zip` 为权威下载目标；即使 Release 下还有单架构 zip，也不能改变这个优先级
- `arm64.zip` 与 `x86_64.zip` 主要用于给明确知道自己机器架构、希望减少下载体积的用户
- `universal.dmg` 主要提供拖拽安装体验，不承担应用内自更新输入

任何产物命名、版本提取规则、zip 结构发生变化时，都必须同步检查：
- `scripts/package-app.sh`
- `.github/workflows/release.yml`
- `CHANGELOG.md`
- `README.md`

## Homebrew
仓库内 `homebrew/skillsmaster.rb` 目前只作为 cask 模板参考，尚未接入当前 GitHub Release workflow。

后续单独接入 Homebrew 时，再额外确认：
- 下载 URL 模式是否仍匹配 Release 产物
- SHA256 计算对象是否未变化
- `brew install --cask skillsmaster` 的安装路径与卸载清理规则是否仍成立

## 高风险检查清单
发布前至少确认：
- `swift test` 通过
- `build/SkillsMaster.app` 可成功生成
- `build/SkillsMaster-v<version>-universal.zip` 可成功生成
- `build/SkillsMaster-v<version>-arm64.zip` 可成功生成
- `build/SkillsMaster-v<version>-x86_64.zip` 可成功生成
- `build/SkillsMaster-v<version>-universal.dmg` 可成功生成
- `CHANGELOG.md` 已记录当前版本的关键变更与缺陷修复
- 通用二进制同时包含 `arm64` 与 `x86_64`
- 单架构 zip 中的二进制分别只包含目标架构
- 资源包、图标与 `Info.plist` 未丢失
- Release 产物命名与 workflow、README 一致
- 当前选择的发布 remote 确实指向 GitHub 仓库；多 remote 时必要时显式传 `--remote`
- 目标分支的 Release commit 已经推送到该 GitHub remote，再创建版本 tag
- 若改动涉及自更新，手动核对下载与安装逻辑是否仍可工作
- 自更新回归时至少覆盖三类真实场景：可写目录原地更新、`/Applications` 下的管理员授权更新、以及 App Translocation / 只读卷下的明确失败提示
