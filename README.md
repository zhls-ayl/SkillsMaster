# SkillsMaster

English | [简体中文](README_CN.md)

SkillsMaster is a native macOS app for managing Skills and Agent root files across multiple AI coding agents from one unified desktop interface.

It brings together operations that are otherwise scattered across the filesystem, symbolic links, lock files, Git repositories, and marketplaces into a single local app.

> Origin: this repository evolved from a fork of [crossoverJie/SkillDeck](https://github.com/crossoverJie/SkillDeck.git) and is now maintained as the standalone `SkillsMaster` product.

## Why SkillsMaster

If you use multiple AI coding agents at the same time, you usually run into the same problems:

- Skills are spread across different directories and are hard to inspect consistently
- `SKILL.md`, frontmatter, source repository, and installation status are difficult to track
- Different agents inherit or read Skills differently, so the real install state is not obvious
- Installing from `Skills.sh`, ClawHub, SkillsHub, or custom repositories is inconsistent
- Manually maintaining symbolic links, physical copies, update checks, and lock files is tedious

SkillsMaster turns those workflows into one native macOS experience.

## Core Capabilities

- Scan and display local Skills, including direct installs and inherited installs
- Search, sort, edit, delete, reassign Agents, and check updates in `Installed > All Skills`
- Browse Agent root directories in `Agent Files` with text preview, built-in editing, Finder/Terminal/external-editor actions
- Configure each Agent's default install mode: `symbolic link` or `physical copy`
- Install Skills from `Skills.sh`, ClawHub, SkillsHub, and custom repositories
- Batch-check updates for Git-backed and SkillsHub-backed Skills
- Self-update the app, prioritizing the `universal.zip` release asset
- Distribute GitHub Release artifacts as `universal.zip`, `arm64.zip`, `x86_64.zip`, and `universal.dmg`
- Support full app UI localization with `English` and `简体中文`, with system-following by default and manual override in Settings

## Install

### Homebrew

```bash
brew tap zhls-ayl/skillsmaster
brew install --cask skillsmaster
```

This is the recommended option for most users.

### GitHub Release

You can also download release artifacts directly:

- `SkillsMaster-v<version>-universal.zip`
- `SkillsMaster-v<version>-arm64.zip`
- `SkillsMaster-v<version>-x86_64.zip`
- `SkillsMaster-v<version>-universal.dmg`

Release page:

- [GitHub Releases](https://github.com/zhls-ayl/SkillsMaster/releases)

### Run from Source

```bash
git clone https://github.com/zhls-ayl/SkillsMaster.git
cd SkillsMaster
./run
```

## Requirements

- macOS 14+
- Xcode 15+
- Swift 5.9+

For inline English-to-Chinese translation in detail pages:

- macOS 26+
- English -> Simplified Chinese offline translation pack installed in the system

## Supported Agents

- Claude Code
- Codex
- Gemini CLI
- GitHub Copilot
- OpenCode
- Antigravity
- Cursor
- Kiro CLI
- CodeBuddy
- OpenClaw
- Trae

## Main Navigation

- `Installed`: inspect, edit, assign, delete, and update local Skills
- `Marketplace`: browse and install from `Skills.sh`, ClawHub, and SkillsHub
- `Repositories`: add SSH, public HTTPS, or token-authenticated HTTPS repositories; then sync, browse, and install from them
- `Agents`: inspect Agent Skills and Agent root files

## Important Paths

- Canonical managed Skills directory: `~/.skillsmaster/skills`
- Compatibility lock file: `~/.agents/.skill-lock.json`
- `Agent Files > skills/` is protected and read-only inside the app
- In-app update requires running from a real `.app` bundle; `swift run`, DMG-mounted apps, and temporary unzip locations are not guaranteed to update in place

## Screenshots

### All Skills

![SkillsMaster All Skills](docs/screenshots/dashboard.png)

### Skill Detail

![SkillsMaster Skill Detail](docs/screenshots/skill-detail.png)

### Skills.sh

![SkillsMaster Skills.sh](docs/screenshots/Skills.sh.png)

### ClawHub

![SkillsMaster ClawHub](docs/screenshots/clawhub.png)

### SkillsHub

![SkillsMaster SkillsHub](docs/screenshots/SkillsHub.png)

### Repositories

![SkillsMaster Repositories](docs/screenshots/Repositories.png)

### Agent Files

![SkillsMaster Agent Files](docs/screenshots/AgentFiles.png)

### Agent Skills

![SkillsMaster Agent Skills](docs/screenshots/AgentSkills.png)

## Common Commands

`./run` is the unified repository entry point. Without arguments it defaults to `./run dev`.

```bash
./run
./run test
./run build -c release
./run package --version 1.2.3 --release-assets
./run release v1.2.3 --remote zhls-ayl --yes
./run ship 1.2.3 --yes
```

## Documentation

- [`README.md`](README.md): English overview, install, quick start, screenshots
- [`README_CN.md`](README_CN.md): Chinese overview, install, quick start, screenshots
- [`docs/Index.md`](docs/Index.md): documentation navigation and update guide
- [`docs/architecture.md`](docs/architecture.md): implementation structure and storage paths
- [`docs/development.md`](docs/development.md): development workflow and verification
- [`docs/release.md`](docs/release.md): packaging, release, Homebrew, and distribution
- [`AGENTS.md`](AGENTS.md): collaboration rules, confirmation boundaries, and validation requirements
