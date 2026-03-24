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
  version "0.2.0"
  sha256 "d982a5d876191ac15bd8d1497f683defb63b3e287137fdc0ffd2f02428f7346b"

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
