import SwiftUI

/// Sidebar navigation item enum
///
/// Each case represents a clickable item in the sidebar.
/// F09 adds `.skillsSh` for browsing the skills.sh catalog.
/// Repository rows use `.repository(UUID)` for user-configured GitHub/GitLab repositories.
enum SidebarItem: Hashable {
    case allSkills
    /// F09: Browse skills.sh catalog (leaderboard + search)
    case skillsSh
    /// Browse ClawHub marketplace
    case clawHub
    /// Browse SkillsHub marketplace
    case skillsHub
    /// Repository browser — each configured repo gets its own sidebar row.
    /// The associated UUID is the SkillRepository.id, used to look up the VM in ContentView.
    case repository(UUID)
    case skillsByAgent(AgentType)
    case agentFiles(AgentType)
    case settings

    /// Maps sidebar options to Agent filter values
    /// - .allSkills / .settings / .skillsSh / .clawHub / .repository → nil
    /// - .skillsByAgent(type) → type (show only skills for this Agent)
    /// This computed property is similar to Java's getter, executes switch calculation on each access
    var agentFilter: AgentType? {
        switch self {
        case .skillsByAgent(let agentType):
            return agentType
        case .allSkills, .settings, .skillsSh, .clawHub, .skillsHub, .repository, .agentFiles:
            return nil
        }
    }
}

/// SidebarView is the app's sidebar navigation
///
/// macOS sidebar visual guidelines (referencing Finder, Mail and other native apps):
/// - Selected: rounded rectangle with accentColor semi-transparent background
/// - Hover: use native .sidebar hover feedback from AppKit
/// - Normal: transparent background
///
/// @Binding is two-way binding (similar to Vue's v-model), parent and child components share the same state
struct SidebarView: View {

    @Binding var selection: SidebarItem?
    @Environment(SkillManager.self) private var skillManager

    /// macOS 14+ provides native SwiftUI action to open settings window
    /// @Environment(\.openSettings) gets the system-provided OpenSettingsAction from environment,
    /// calling openSettings() is equivalent to user pressing Cmd+, (more reliable than NSApp.sendAction)
    @Environment(\.openSettings) private var openSettings

    private var skillAgentTypes: [AgentType] {
        AgentType.displayNameLengthSortedCases
    }

    private var fileAgentTypes: [AgentType] {
        let supported = Set(
            skillManager.agents
                .filter(\.supportsRootFileManagement)
                .map(\.type)
        )
        return AgentType.displayNameLengthSortedCases.filter { supported.contains($0) }
    }

    var body: some View {
        List(selection: $selection) {
            // Section creates groups (shown as collapsible groups in macOS sidebar)
            Section(AppLocalization.string("Installed")) {
                sidebarRow {
                    Label(AppLocalization.string("All Skills"), systemImage: "square.grid.2x2")
                }
                .badge(skillManager.skills.count)
                // IMPORTANT: keep .tag as the outermost row modifier.
                // List(selection:) reads tags from the final row container.
                // If .tag is applied inside sidebarRow() and then wrapped by
                // .badge/.opacity/.listRowBackground, some rows become non-selectable.
                .tag(SidebarItem.allSkills)

            }

            // F09: skills.sh browser — browse and search the online catalog
            Section(AppLocalization.string("Marketplace")) {
                sidebarRow {
                    Label(AppLocalization.string("Skills.sh"), systemImage: "globe")
                }
                .tag(SidebarItem.skillsSh)

                sidebarRow {
                    Label(AppLocalization.string("ClawHub"), systemImage: "shippingbox")
                }
                .tag(SidebarItem.clawHub)

                sidebarRow {
                    Label(AppLocalization.string("SkillsHub"), systemImage: "shippingbox.circle")
                }
                .tag(SidebarItem.skillsHub)
            }

            // Repositories section: shown only when at least one repository is configured
            // ForEach on an empty array renders nothing, so the section header would still appear.
            // We wrap in an `if !isEmpty` guard to fully hide the section when no repos are configured.
            if !skillManager.repositories.isEmpty {
                Section(AppLocalization.string("Repositories")) {
                    ForEach(skillManager.repositories) { repo in
                        let item = SidebarItem.repository(repo.id)
                        let syncStatus = skillManager.repoSyncStatuses[repo.id] ?? .idle

                        sidebarRow {
                            Label {
                                Text(repo.name)
                            } icon: {
                                // Show a spinner when syncing, otherwise the platform icon
                                if case .syncing = syncStatus {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: repo.platform.iconName)
                                        .foregroundStyle(
                                            syncStatus == .idle
                                                ? Color.secondary
                                                : (syncErrorStatus(syncStatus) ? Color.red : Color.green)
                                        )
                                }
                            }
                        }
                        .tag(item)
                    }
                }
            }

            Section(AppLocalization.string("Agents")) {
                DisclosureGroup(AppLocalization.string("Agent Files")) {
                    ForEach(fileAgentTypes) { agentType in
                        sidebarRow {
                            Label {
                                Text(agentType.displayName)
                            } icon: {
                                AgentIconView(agentType: agentType, size: 16)
                            }
                        }
                        .tag(SidebarItem.agentFiles(agentType))
                    }
                }

                DisclosureGroup(AppLocalization.string("Agents Skills")) {
                    ForEach(skillAgentTypes) { agentType in
                        let agent = skillManager.agents.first { $0.type == agentType }

                        sidebarRow {
                            Label {
                                Text(agentType.displayName)
                            } icon: {
                                AgentIconView(agentType: agentType, size: 16)
                            }
                        }
                        .badge(skillManager.skills(for: agentType).count)
                        // Use skillManager.skills(for:) instead of agent?.skillCount,
                        // because the latter only counts skills in Agent's own directory (from AgentDetector),
                        // not including inherited installations (like Copilot inheriting skills from Claude directory)
                        // opacity controls transparency: uninstalled Agents are shown semi-transparent
                        .opacity(agent?.isInstalled == true ? 1.0 : 0.5)
                        .tag(SidebarItem.skillsByAgent(agentType))
                    }
                }
            }
        }
        // macOS sidebar standard style
        .listStyle(.sidebar)
        .navigationTitle(AppLocalization.string("SkillsMaster"))
        // Sidebar top toolbar action buttons (native macOS toolbar style)
        // Works with .navigationSplitViewColumnWidth(min: 180) minimum width constraint in ContentView,
        // ensures sidebar won't be too narrow when window state is restored, preventing ToolbarItem overflow/hiding
        .toolbar {
            // App update reminder button: shows orange upward arrow when new version is available
            // Opens settings window when clicked (by sending system notification showSettingsWindow)
            // Only shows when appUpdateInfo is not nil, users will notice this newly appearing icon
            ToolbarItem {
                if skillManager.appUpdateInfo != nil {
                    Button {
                        // openSettings() is macOS 14+ native SwiftUI API,
                        // equivalent to user pressing Cmd+, opens settings window defined in Settings { } scene
                        openSettings()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .help(AppLocalization.string("Update available, click to open Settings."))
                }
            }

            // F12: Batch check updates for all skills
            ToolbarItem {
                Button {
                    Task { await skillManager.checkAllUpdates() }
                } label: {
                    // When checking, shows spinning progress indicator (ProgressView) + progress count (e.g., 3/12),
                    // otherwise shows static icon
                    if skillManager.isCheckingUpdates {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            // Progress count: counts number of skills that have completed checking / total pending check count
                            // Skills in .checking state are still being checked, others (.hasUpdate/.upToDate/.error) indicate completed
                            let total = skillManager.skills.filter { skill in
                                guard let sourceType = skill.lockEntry?.sourceType else { return false }
                                return sourceType != "local" && sourceType != "clawhub"
                            }.count
                            // compactMap is similar to Java Stream's filter+map combination:
                            // first get value from dictionary (may be nil), then filter out .checking state
                            let checked = skillManager.updateStatuses.values.filter {
                                $0 != .checking && $0 != .notChecked
                            }.count
                            Text("\(checked)/\(total)")
                                .font(.caption)
                                .monospacedDigit()  // Monospaced digit font, avoids width jumping when numbers change
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help(AppLocalization.string("Check all Skills for updates"))
                .disabled(skillManager.isCheckingUpdates)
            }

            // Refresh button: rescan file system
            ToolbarItem {
                Button {
                    Task { await skillManager.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(AppLocalization.string("Refresh Skills"))
            }
        }
    }

    /// Build sidebar row view, unified handling for row hit-testing and List selection wiring
    ///
    /// @ViewBuilder allows closure to return different View types (similar to Java's generic methods)
    /// `some View` is Swift's opaque return type,
    /// means "returns some View, but caller doesn't need to know the specific type"
    @ViewBuilder
    private func sidebarRow<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        // Keep row content as a plain view and let List(selection:) own the selection lifecycle.
        // This follows AppKit/SwiftUI best practice: avoid manually writing selection state
        // from gesture handlers inside table rows, which can cause NSTableView delegate reentrancy.
        label()
            // Expand interaction area (click + hover) to the full row rectangle.
            .contentShape(Rectangle())
    }

    /// Returns true if the given SyncStatus represents an error state.
    /// Used to decide the icon foreground color in the Repositories section.
    private func syncErrorStatus(_ status: SkillRepository.SyncStatus) -> Bool {
        if case .error = status { return true }
        return false
    }
}
