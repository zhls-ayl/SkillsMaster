# 打包与发布（Release）

## 本地打包脚本
仓库当前使用以下脚本维护发布链路：
- `scripts/package-app.sh`：构建通用二进制、组装 `.app`、可选生成 zip
- `scripts/release.sh`：校验工作区、版本号、远端同步状态，并创建 / 推送 tag
- `scripts/run.sh`：本地运行入口，处理模块缓存与工具链异常提示
- `CHANGELOG.md`：发布记录与已修复缺陷入口；每次准备发布版本时都应同步更新

## 标准本地发布流程
```bash
swift test
./scripts/package-app.sh --version 1.2.3 --zip
./scripts/release.sh v1.2.3
```

其中：
- `package-app.sh` 会检查 `xcode-select`、`actool`、二进制架构与资源包
- `release.sh` 要求工作区干净、分支已配置 upstream、目标 tag 不存在
- `CHANGELOG.md` 应至少包含该版本的 `Added` / `Changed` / `Fixed` 中实际发生的内容；若本次发布以修复缺陷为主，应优先记录缺陷现象与修复范围

## GitHub Actions
- `.github/workflows/ci.yml`
  - 在 `push main` 和 `pull_request` 时执行 `swift build` 与 `swift test`
- `.github/workflows/release.yml`
  - 在推送 `v*` tag 时执行测试、构建 `.app`、打 zip、创建 GitHub Release
  - 成功后会更新 Homebrew tap 仓库中的 cask 版本与 SHA256

## 发布产物
当前发布产物命名为：
- `SkillsMaster.app`
- `SkillsMaster-v<version>-universal.zip`

任何产物命名、版本提取规则、zip 结构发生变化时，都必须同步检查：
- `scripts/package-app.sh`
- `.github/workflows/release.yml`
- `homebrew/skillsmaster.rb`
- `CHANGELOG.md`
- `README.md`

## Homebrew
仓库内 `homebrew/skillsmaster.rb` 是 cask 模板参考；实际自动更新由 Release workflow 推送到 tap 仓库完成。

如果发布流程调整，需要特别确认：
- 下载 URL 模式是否仍匹配 Release 产物
- SHA256 计算对象是否未变化
- `brew install --cask skillsmaster` 的安装路径与卸载清理规则是否仍成立

## 高风险检查清单
发布前至少确认：
- `swift test` 通过
- `build/SkillsMaster.app` 可成功生成
- `CHANGELOG.md` 已记录当前版本的关键变更与缺陷修复
- 通用二进制同时包含 `arm64` 与 `x86_64`
- 资源包、图标与 `Info.plist` 未丢失
- Release 产物命名与 workflow、Homebrew 一致
- 若改动涉及自更新，手动核对下载与安装逻辑是否仍可工作
