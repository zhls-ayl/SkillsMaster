# Homebrew Cask for SkillsMaster release assets
#
# 这个文件用于发布到自有 tap，例如 `zhls-ayl/homebrew-skillsmaster`。
#
# 使用方法：
#   1. 创建一个新仓库: github.com/zhls-ayl/homebrew-skillsmaster
#   2. 将此文件放在: Casks/skillsmaster.rb
#   3. 每次发布新版本时，更新 version / sha256
#
# 用户安装命令：
#   brew tap zhls-ayl/skillsmaster
#   brew install --cask skillsmaster
#
# 计算 sha256：
#   shasum -a 256 SkillsMaster-vX.Y.Z-universal.zip

cask "skillsmaster" do
  version "0.2.15"
  sha256 "75b6a581b6477e0f1d0d78186e31a8886cc8f7a0ffd49397ae3c737a37ff9e7f"

  url "https://github.com/zhls-ayl/SkillsMaster/releases/download/v#{version}/SkillsMaster-v#{version}-universal.zip"
  name "SkillsMaster"
  desc "Native macOS application for managing AI code agent skills"
  homepage "https://github.com/zhls-ayl/SkillsMaster"

  # 要求 macOS Sonoma 或更高版本
  depends_on macos: ">= :sonoma"

  # 告诉 Homebrew 将 .app 移动到 /Applications/
  app "SkillsMaster.app"

  # zap 定义完全卸载时需要清理的文件
  # 只在 brew zap（非 brew uninstall）时执行
  zap trash: [
    "~/.skillsmaster/.skill-lock.json",
    "~/.agents/.skill-lock.json",
  ]
end
