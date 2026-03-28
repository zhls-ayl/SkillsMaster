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
- 若 GitHub `main` 开启“必须通过 Pull Request 合并”，发布准备提交也应先走 PR；不要把“推送版本提交”和“推送版本 tag”混为同一步

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
  - 在推送 `v*` tag 时执行测试、构建 release matrix、并通过 `gh` CLI 创建或更新 GitHub Release
  - 当前只负责 GitHub Release 产物，不再联动 Homebrew tap
  - workflow 文件内显式声明 `permissions: contents: write`，用于创建 Release；当前不需要把仓库默认 `Workflow permissions` 提升为全局 write
  - 为规避 GitHub Actions 上 Node 20 JavaScript action 弃用告警，workflow 已升级 `actions/checkout`，并移除了 `softprops/action-gh-release` 依赖

## 本次发布复盘（v0.2.6）
这次 `v0.2.6` 发布实际经历了完整的失败恢复链路，暴露出几条值得固化的规则：

### 发生了什么
- 首次 `v0.2.6` Release workflow 在 `Run tests` 阶段失败，原因不是发布脚本，而是 `TranslationServiceTests` 里对并发调用顺序做了错误假设；本地通过、CI 失败，属于典型 flaky test。
- 修复测试后，主仓库由于 `main` 受分支保护，必须先走 PR 合并，再重新发布 tag。
- GitHub Release 成功后，仓库内 `homebrew/skillsmaster.rb` 与独立 tap `zhls-ayl/homebrew-skillsmaster` 还需要第二阶段同步；它们依赖发布后才能拿到的真实 `universal.zip` digest。

### 更高效的工作流
推荐以后统一按下面顺序执行，而不是在发布过程中交叉回填：

1. 在主仓库把目标版本的代码、测试、`CHANGELOG.md` 全部合入 `main`
2. 运行 `./run test`
3. 运行 `./run package --version X.Y.Z --release-assets`
4. 确认当前本地 `main` 跟踪的是会触发 GitHub Release 的 GitHub remote，而不是镜像或内部 `origin`
5. 执行 `./run release vX.Y.Z --remote <github-remote> --yes`
6. 等待 GitHub Release workflow 成功，确认 `universal.zip`、单架构 zip 与 dmg 都已上传
7. 读取 `universal.zip` 的真实 `sha256`
8. 依次更新本仓库 `homebrew/skillsmaster.rb` 与独立 tap 仓库 `Casks/skillsmaster.rb`

这样可以把“应用发布”和“Homebrew 分发同步”分成两个清晰阶段，减少中途回滚与重复验证。

### 失败恢复规则
- 如果 Release workflow 失败在测试或打包阶段，且 GitHub 上还没有正式 Release 记录，可以在修复问题后删除错误 tag，再从修复后的 `main` 重发同一个版本号。
- 如果 GitHub 上已经创建了正式 Release 或用户已经可能下载到该版本，不要复用同一版本号；应改发新版本，并在 `CHANGELOG.md` 里明确说明补救范围。
- 恢复发布前，先用 `gh release view vX.Y.Z` 确认是否已经存在 Release，再决定“删 tag 重发”还是“ bump 新版本”。

### 这次暴露出的测试教训
- 并发测试不要断言 `async let` 或 task 启动顺序，例如 `["One", "Two"]` 这样的调用顺序在本地和 CI 上都可能不同。
- 对 `TranslationService` 这类并发敏感逻辑，更稳定的断言应放在：
  - 返回值是否正确
  - 相同输入是否被去重
  - 不同输入是否满足串行化 / 单飞约束
  - `maxConcurrentCallCount` 是否符合预期

### Homebrew 同步规则
- `homebrew/skillsmaster.rb` 和独立 tap 中的 cask 都必须使用 GitHub Release 已上传的 `SkillsMaster-vX.Y.Z-universal.zip` 的真实 digest。
- 不要在 Release 成功前先修改 cask 版本和 `sha256`，否则 tap 会短暂进入“版本已更新但下载校验必然失败”的坏状态。
- 仓库内 cask 只是 tap 的源模板；真正给用户使用的是独立 tap 仓库，因此发布收尾默认应包含“同步 tap 仓库”这一步，而不是只改当前仓库。

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
仓库内 `homebrew/skillsmaster.rb` 当前已对齐到最近发布版本，可直接作为自有 tap 中 `Casks/skillsmaster.rb` 的基础文件。

推荐发布方式：
- 新建仓库 `zhls-ayl/homebrew-skillsmaster`
- 把当前文件放到该仓库的 `Casks/skillsmaster.rb`
- 每次发布后，用对应 `universal.zip` 的真实 `sha256` 更新 cask
- 用户通过 `brew tap zhls-ayl/skillsmaster && brew install --cask skillsmaster` 安装

当前不建议直接把本仓库当作 tap：
- `brew tap <user>/<repo>` 默认要求仓库名满足 `homebrew-<name>` 约定
- 把 cask 单独放在 tap 仓库里，升级和校验都会更清晰

### 自有 tap 仓库最小结构
```text
homebrew-skillsmaster/
├── Casks/
│   └── skillsmaster.rb
└── README.md
```

首发时建议的 `README.md` 最小内容：

```text
# homebrew-skillsmaster

brew tap zhls-ayl/skillsmaster
brew install --cask skillsmaster
```

### 首次发布到自有 tap
假设你已经在 GitHub 上创建了 `zhls-ayl/homebrew-skillsmaster`：

```bash
git clone https://github.com/zhls-ayl/homebrew-skillsmaster.git
cd homebrew-skillsmaster
mkdir -p Casks
cp /path/to/SkillsMaster/homebrew/skillsmaster.rb Casks/skillsmaster.rb
git add Casks/skillsmaster.rb README.md
git commit -m "cask: add skillsmaster 0.2.5"
git push origin main
```

### 后续版本更新 tap 的固定流程
1. 先确认 GitHub Release 已经完成，并且 `universal.zip` 已上传成功
2. 取对应版本 `universal.zip` 的真实 `sha256`
3. 先更新当前仓库 `homebrew/skillsmaster.rb`，保持模板与最新发布一致
4. 再更新 tap 仓库里的 `Casks/skillsmaster.rb`
5. 提交并推送 tap 仓库

如果本机已安装 `gh`，可以直接用下面的命令取某个版本 `universal.zip` 的 digest：

```bash
gh release view v0.2.5 --repo zhls-ayl/SkillsMaster --json assets | \
  ruby -rjson -e 'data=JSON.parse(STDIN.read); asset=data.fetch("assets").find { |a| a["name"] == "SkillsMaster-v0.2.5-universal.zip" }; puts asset.fetch("digest")'
```

得到的结果形如：

```text
sha256:6e0974f53f007926542f2cb74a7e9fbc1a5f9826b1189ac5464f2464af45bdb9
```

把前缀 `sha256:` 去掉后，填回 `Casks/skillsmaster.rb` 的 `sha256` 字段即可。

后续单独接入 Homebrew 时，再额外确认：
- 下载 URL 模式是否仍匹配 Release 产物
- SHA256 计算对象是否未变化
- `brew install --cask skillsmaster` 的安装路径与卸载清理规则是否仍成立
- tap 仓库是否已经同步到与主仓库 cask 模板相同的版本与 digest

## 高风险检查清单
发布前至少确认：
- `swift test` 通过
- 与本次改动直接相关的并发 / CI 敏感测试没有把任务调度顺序当作稳定行为
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
- 当前本地分支跟踪的上游确实是预期的 GitHub remote；若 `main` 不跟踪 GitHub remote，先修正 upstream 再打 tag
- 目标分支的 Release commit 已经推送到该 GitHub remote，再创建版本 tag
- 若仓库 `main` 受分支保护，版本相关提交先通过 PR 合入，再创建版本 tag；不要尝试直接推送 `main`
- 若改动涉及自更新，手动核对下载与安装逻辑是否仍可工作
- 自更新回归时至少覆盖三类真实场景：可写目录原地更新、`/Applications` 下的管理员授权更新、以及 App Translocation / 只读卷下的明确失败提示
- 发布完成后，继续核对 GitHub Release、仓库内 cask 模板、独立 tap 仓库这三处是否全部已同步到同一版本
