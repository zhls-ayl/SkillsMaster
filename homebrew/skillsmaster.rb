# Homebrew Cask Formula Template for SkillsMaster
#
# 这个文件是 Homebrew Cask 配方的模板，用于 `brew install --cask skillsmaster`
#
# 使用方法：
#   1. 创建一个新仓库: github.com/zhls-ayl/homebrew-skillsmaster
#   2. 将此文件放在: Casks/skillsmaster.rb
#   3. 每次发布新版本时，更新 version 和 sha256
#
# 用户安装命令：
#   brew tap zhls-ayl/skillsmaster
#   brew install --cask skillsmaster
#
# 计算 sha256：
#   shasum -a 256 SkillsMaster-vX.Y.Z-universal.zip

cask "skillsmaster" do
  version "0.1.3"
  sha256 "51459fb1544274e4d56a7a1f9730449fb0786141868f2cb982a2734c803e8879"

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
    "~/.agents/.skill-lock.json",
  ]
end
