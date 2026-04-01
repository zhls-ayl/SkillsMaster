import AppKit
import SwiftUI

/// RepositoriesSettingsView — Settings tab for managing custom Git repositories.
///
/// Displays a list of user-configured repositories (SSH / HTTPS Public / HTTPS+Token) and
/// allows adding new ones or removing existing ones.
///
/// Accessed via Settings (Cmd+,) → "Repositories" tab.
struct RepositoriesSettingsView: View {

    @Environment(SkillManager.self) private var skillManager

    /// Controls visibility of the "添加 Repository" sheet
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository list or empty state
            if skillManager.repositories.isEmpty {
                // Empty state: centered message with add button
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text(appLocalized("No Custom Repositories"))
                        .font(.headline)

                    Text(appLocalized("Add a Git repository or import local SKILL.md content as a custom Skills source."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    Button(appLocalized("Add Repository")) {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Repository list
                List {
                    ForEach(skillManager.repositories) { repo in
                        RepositoryRowView(repo: repo)
                    }
                    .onDelete { indexSet in
                        // SwiftUI's onDelete provides the index set of rows to remove
                        for idx in indexSet {
                            let id = skillManager.repositories[idx].id
                            Task { await skillManager.removeRepository(id: id) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Bottom toolbar: "+" add button
            HStack {
                // "+" button: shows add repository sheet
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(appLocalized("Add a custom repository"))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        // 添加 Repository sheet
        .sheet(isPresented: $showAddSheet) {
            AddRepositorySheet(isPresented: $showAddSheet)
                .environment(skillManager)
        }
    }
}

// MARK: - Repository Row

/// Displays a single repository row in the settings list.
private struct RepositoryRowView: View {

    @Environment(SkillManager.self) private var skillManager
    let repo: SkillRepository
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var isRemoving = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isLocalCollection ? "externaldrive.badge.plus" : repo.platform.iconName)
                .foregroundStyle(repo.isLocalCollection ? Color.accentColor : (repo.platform == .github ? Color.primary : Color.orange))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Display name
                Text(repo.name)
                    .font(.body)
                    .fontWeight(.medium)

                if repo.isLocalCollection {
                    Text(appLocalized("Imported local skills grouped under a fixed local source."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        Text(repo.authType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(repo.repoURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            // Last synced timestamp or "Never"
            VStack(alignment: .trailing, spacing: 2) {
                if repo.isLocalCollection {
                    Text(appLocalized("Managed Locally"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let date = repo.effectiveLastSyncedAt {
                    Text(appLocalized("Synced"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(gitStyleRelativeTime(from: date, now: context.date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .help(absoluteDateText(date))
                } else {
                    Text(appLocalized("Never synced"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 同步 status indicator
            syncStatusView

            if !repo.isLocalCollection {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help(appLocalized("Edit repository settings"))
                .disabled(isRemoving)
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                if isRemoving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)
            .help(appLocalized("Remove repository"))
            .disabled(isRemoving)
        }
        .padding(.vertical, 2)
        .alert(appLocalized("Remove Repository?"), isPresented: $showDeleteConfirmation) {
            Button(appLocalized("Remove"), role: .destructive) {
                Task { await removeRepository() }
            }
            Button(appLocalized("Cancel"), role: .cancel) { }
        } message: {
            Text(
                repo.isLocalCollection
                    ? appLocalized("This removes the LocalSkill source entry from SkillsMaster. Imported skills already copied into the library are kept.")
                    : appLocalized("This removes the repository config from SkillsMaster. Local clone files are kept.")
            )
        }
        .sheet(isPresented: $showEditSheet) {
            EditRepositorySheet(repo: repo, isPresented: $showEditSheet)
                .environment(skillManager)
        }
    }

    /// Small inline sync status indicator
    @ViewBuilder
    private var syncStatusView: some View {
        let status = skillManager.repoSyncStatuses[repo.id] ?? .idle
        switch status {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
        case .success(let date):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help(AppLocalization.format("Last sync succeeded at %@", absoluteDateText(date)))
        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .help(message)
        }
    }

    private func removeRepository() async {
        isRemoving = true
        await skillManager.removeRepository(id: repo.id)
        isRemoving = false
    }

    /// Compact relative time style similar to git UIs (e.g. "3m ago", "2h ago", "yesterday").
    private func gitStyleRelativeTime(from date: Date, now: Date) -> String {
        AppLocalization.relativeDateTime(from: date, to: now)
    }

    /// Full timestamp shown on hover so users can inspect exact sync time.
    private func absoluteDateText(_ date: Date) -> String {
        AppLocalization.absoluteDateTime(date)
    }
}

// MARK: - Edit Repository Sheet

/// Sheet for editing existing repository settings.
///
/// Editable fields:
/// - Display name
/// - 同步 on Launch
/// - Scan hidden paths
///
/// Read-only fields:
/// - Authentication
/// - Repository URL
private struct EditRepositorySheet: View {

    @Environment(SkillManager.self) private var skillManager
    let repo: SkillRepository
    @Binding var isPresented: Bool

    @State private var displayName: String
    @State private var syncOnLaunch: Bool
    @State private var scanHiddenPaths: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(repo: SkillRepository, isPresented: Binding<Bool>) {
        self.repo = repo
        self._isPresented = isPresented
        self._displayName = State(initialValue: repo.name)
        self._syncOnLaunch = State(initialValue: repo.syncOnLaunch)
        self._scanHiddenPaths = State(initialValue: repo.scanHiddenPaths)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appLocalized("Edit Repository"))
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Display Name"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                TextField(appLocalized("e.g. team-skills"), text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(appLocalized("Sync on Launch"), isOn: $syncOnLaunch)
                    .help(appLocalized("Controls only startup auto-sync. Manual 'Sync Now' is always available."))
                Text(syncOnLaunch
                     ? appLocalized("This repository will auto-sync when SkillsMaster starts.")
                     : appLocalized("No startup auto-sync. Use 'Sync Now' when needed."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(appLocalized("Scan hidden paths"), isOn: $scanHiddenPaths)
                    .help(appLocalized("When enabled, SKILL.md files under hidden path segments (e.g. .claude) are included."))
                Text(scanHiddenPaths
                     ? appLocalized("Hidden path scanning is enabled for this repository.")
                     : appLocalized("Only non-hidden paths are scanned for this repository."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(appLocalized("Authentication"))
                        .foregroundStyle(.secondary)
                    Text(repo.authType.displayName)
                }
                GridRow {
                    Text(appLocalized("Repository URL"))
                        .foregroundStyle(.secondary)
                    Text(repo.repoURL)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.caption)

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }

            Spacer()

            HStack {
                Button(appLocalized("Cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isSaving ? appLocalized("Saving…") : appLocalized("Save")) {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 500, height: 420)
    }

    private func save() async {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = appLocalized("Display Name cannot be empty")
            return
        }

        isSaving = true
        errorMessage = nil

        var updated = repo
        updated.name = trimmedName
        updated.syncOnLaunch = syncOnLaunch
        updated.scanHiddenPaths = scanHiddenPaths

        await skillManager.updateRepository(updated)
        isSaving = false
        isPresented = false
    }
}

// MARK: - 添加 Repository Sheet

/// Sheet for adding a new custom repository.
///
/// User fills in:
/// - Repository URL (required): SSH or HTTPS
/// - Optional HTTPS credentials (username + token)
/// - Display name (optional, auto-derived from URL if empty)
/// - Startup sync switch (default off)
/// - Hidden-path scan switch (default off)
///
/// On confirm: creates a SkillRepository, calls SkillManager.addRepository(), then syncs.
struct AddRepositorySheet: View {

    private enum SourceMode: String, CaseIterable {
        case gitRepository
        case localSkill

        var displayName: String {
            switch self {
            case .gitRepository:
                return AppLocalization.string("Git Repository")
            case .localSkill:
                return AppLocalization.string("Local Skill")
            }
        }
    }

    private enum LocalImportConflictResolution {
        case replace
        case skip
        case cancelAll
    }

    struct LocalImportDraft: Identifiable {
        let candidate: LocalSkillImportService.Candidate
        let skillName: String

        var id: String {
            "\(candidate.id)::\(skillName)"
        }
    }

    private struct LocalImportConflict: Identifiable {
        let draft: LocalImportDraft
        let existingSkill: Skill

        var id: String {
            draft.id
        }
    }

    struct LocalImportResult: Identifiable {
        enum Status: Equatable {
            case imported
            case replaced
            case skipped
            case failed
            case cancelled

            var iconName: String {
                switch self {
                case .imported, .replaced:
                    return "checkmark.circle.fill"
                case .skipped:
                    return "arrow.turn.down.right"
                case .failed:
                    return "xmark.circle.fill"
                case .cancelled:
                    return "stop.circle.fill"
                }
            }

            var color: Color {
                switch self {
                case .imported, .replaced:
                    return .green
                case .skipped:
                    return .orange
                case .failed, .cancelled:
                    return .red
                }
            }

            var title: String {
                switch self {
                case .imported:
                    return AppLocalization.string("Imported")
                case .replaced:
                    return AppLocalization.string("Replaced")
                case .skipped:
                    return AppLocalization.string("Skipped")
                case .failed:
                    return AppLocalization.string("Failed")
                case .cancelled:
                    return AppLocalization.string("Cancelled")
                }
            }
        }

        let draft: LocalImportDraft
        let status: Status
        let message: String?

        var id: String {
            draft.id
        }
    }

    @Environment(SkillManager.self) private var skillManager
    @Binding var isPresented: Bool

    // Form state
    @State private var sourceMode: SourceMode = .gitRepository
    @State private var repoURL = ""
    @State private var authType: SkillRepository.AuthType = .ssh
    @State private var httpUsername = "git"
    @State private var accessToken = ""
    @State private var displayName = ""
    @State private var syncOnLaunch = false
    @State private var scanHiddenPaths = false
    @State private var localSelectionURL: URL?
    @State private var localCandidates: [LocalSkillImportService.Candidate] = []
    @State private var singleFileSkillName = ""
    @State private var isScanningLocalSelection = false
    @State private var pendingConflict: LocalImportConflict?
    @State private var importResults: [LocalImportResult] = []
    @State private var showImportSummary = false
    @State private var conflictContinuation: CheckedContinuation<LocalImportConflictResolution, Never>?
    @State private var isAdding = false
    @State private var errorMessage: String?

    /// Whether the form input is valid enough to enable the Add button
    private var canAdd: Bool {
        switch sourceMode {
        case .gitRepository:
            let urlValid = !repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let tokenValid = !authType.requiresToken || !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return urlValid && tokenValid && !isAdding
        case .localSkill:
            let hasSelection = localSelectionURL != nil && !localCandidates.isEmpty
            let customNameValid = localCandidates.allSatisfy { candidate in
                !candidate.requiresCustomName || !singleFileSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return hasSelection && customNameValid && !isAdding && !isScanningLocalSelection
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sheet title
            Text(appLocalized("Add Custom Repository"))
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Source Type"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                Picker(appLocalized("Source Type"), selection: $sourceMode) {
                    ForEach(SourceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: sourceMode) { _, _ in
                    errorMessage = nil
                }
            }

            if sourceMode == .gitRepository {
                gitRepositoryForm
            } else {
                localSkillImportForm
            }

            // Error message (shown if add fails)
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }

            Spacer()

            // Action buttons
            HStack {
                Button(appLocalized("Cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)  // Esc key dismisses

                Spacer()

                Button(primaryButtonTitle) {
                    Task { await primaryAction() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)  // Enter key confirms
            }
        }
        .padding(20)
        .frame(width: 560, height: sourceMode == .localSkill ? 680 : (authType.requiresToken ? 610 : 500))
        .alert(
            appLocalized("Skill Already Exists"),
            isPresented: Binding(
                get: { pendingConflict != nil },
                set: { if !$0 { pendingConflict = nil } }
            )
        ) {
            Button(appLocalized("Replace"), role: .destructive) {
                resolveConflict(.replace)
            }
            Button(appLocalized("Skip")) {
                resolveConflict(.skip)
            }
            Button(appLocalized("Cancel All"), role: .cancel) {
                resolveConflict(.cancelAll)
            }
        } message: {
            if let pendingConflict {
                Text(
                    AppLocalization.format(
                        "A skill named \"%@\" already exists. Do you want to replace it?",
                        pendingConflict.draft.skillName
                    )
                )
            }
        }
        .sheet(isPresented: $showImportSummary) {
            LocalImportSummarySheet(results: importResults, isPresented: $showImportSummary)
        }
        .onChange(of: scanHiddenPaths) { _, _ in
            guard sourceMode == .localSkill, let localSelectionURL else { return }
            Task { await scanLocalSelection(localSelectionURL) }
        }
    }

    @ViewBuilder
    private var gitRepositoryForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Authentication"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                Picker(appLocalized("Authentication"), selection: $authType) {
                    ForEach(SkillRepository.AuthType.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: authType) { _, newValue in
                    applyAuthTypeChange(newValue)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Repository URL"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                TextField(
                    authType == .ssh ? appLocalized("git@host:org/repo.git") : appLocalized("https://host/org/repo.git"),
                    text: $repoURL
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: repoURL) { _, _ in
                    errorMessage = nil
                    if displayName.isEmpty {
                        let slug = SkillRepository.slugFrom(repoURL: repoURL)
                        if !slug.isEmpty && slug != repoURL {
                            displayName = slug
                        }
                    }
                }

                Text(authDescriptionText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if authType.requiresToken {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized("HTTPS Username"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    TextField(appLocalized("git"), text: $httpUsername)
                        .textFieldStyle(.roundedBorder)

                    Text(appLocalized("For GitHub, 'x-access-token' or your username both work; enterprise Git may require account username."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized("Access Token"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    SecureField(appLocalized("Enter PAT token"), text: $accessToken)
                        .textFieldStyle(.roundedBorder)

                    Text(appLocalized("Token is stored securely in macOS Keychain, not in config files."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Display Name"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                TextField(appLocalized("e.g. team-skills"), text: $displayName)
                    .textFieldStyle(.roundedBorder)

                Text(appLocalized("How this repository appears in the sidebar."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(appLocalized("Sync on Launch"), isOn: $syncOnLaunch)
                    .help(appLocalized("When enabled, this repository auto-syncs when SkillsMaster starts. Disabled by default for better startup performance."))

                Text(syncOnLaunch
                     ? appLocalized("This repository will auto-sync at app startup.")
                     : appLocalized("Default mode: no startup auto-sync. You can always sync manually with 'Sync Now'."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(appLocalized("Scan hidden paths"), isOn: $scanHiddenPaths)
                    .help(appLocalized("Disabled by default to avoid duplicate/ambiguous skills from hidden mirrors. Enable only when your skills are intentionally stored under hidden directories."))

                Text(scanHiddenPaths
                     ? appLocalized("Includes SKILL.md under hidden folders (path segments starting with '.').")
                     : appLocalized("Default mode: only scans non-hidden paths. This avoids accidental duplicates from hidden mirror folders."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var localSkillImportForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Local Import"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                Button {
                    chooseLocalImportSelection()
                } label: {
                    Label(appLocalized("Choose SKILL.md or Folder…"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)

                if let localSelectionURL {
                    Text(localSelectionURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                } else {
                    Text(appLocalized("Select a SKILL.md file, a single skill folder, or a parent folder for recursive scanning."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(appLocalized("Scan hidden paths"), isOn: $scanHiddenPaths)
                    .help(appLocalized("When enabled, SKILL.md files under hidden path segments (e.g. .claude) are included."))

                Text(scanHiddenPaths
                     ? appLocalized("Hidden folders are included while scanning the selected directory.")
                     : appLocalized("Default mode: hidden folders are skipped only during directory-result filtering."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if isScanningLocalSelection {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appLocalized("Scanning local skills…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let candidate = localCandidates.first, candidate.requiresCustomName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized("Skill Name"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    TextField(appLocalized("Enter skill name"), text: $singleFileSkillName)
                        .textFieldStyle(.roundedBorder)

                    Text(appLocalized("Used as the UI display name, destination folder name, and immutable skill id."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !localCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.format("Detected %d import candidate(s)", localCandidates.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(localCandidates, id: \.id) { candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(candidateDisplayName(candidate))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if candidate.requiresCustomName {
                                            Text(appLocalized("Name Required"))
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.14))
                                                .foregroundStyle(.orange)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    if !candidate.metadata.description.isEmpty {
                                        Text(candidate.metadata.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Text(candidate.sourceURL.path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
    }

    private var authDescriptionText: String {
        switch authType {
        case .ssh:
            return appLocalized("SSH requires keys configured in ~/.ssh")
        case .httpsPublic:
            return appLocalized("Use HTTPS URL for a public repository that allows anonymous clone")
        case .httpsToken:
            return appLocalized("Use HTTPS URL with a Personal Access Token")
        }
    }

    private var primaryButtonTitle: String {
        if isAdding {
            return sourceMode == .localSkill ? appLocalized("Importing…") : appLocalized("Adding…")
        }
        return sourceMode == .localSkill ? appLocalized("Import Skills") : appLocalized("Add Repository")
    }

    private func primaryAction() async {
        switch sourceMode {
        case .gitRepository:
            await addGitRepository()
        case .localSkill:
            await importLocalSkills()
        }
    }

    /// Validate input, create SkillRepository, add via SkillManager, then trigger sync.
    private func addGitRepository() async {
        let url = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let validationError = SkillRepository.validate(repoURL: url, authType: authType) {
            errorMessage = validationError
            return
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if authType.requiresToken && token.isEmpty {
            errorMessage = appLocalized("Access Token is required for HTTPS mode")
            return
        }

        isAdding = true
        errorMessage = nil

        // Derive display name from URL if user left it blank
        let name: String
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = SkillRepository.slugFrom(repoURL: url)
        } else {
            name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let repoID = UUID()
        let credentialKey = authType.requiresToken ? repoID.uuidString : nil
        let username = httpUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build the SkillRepository model
        let repo = SkillRepository(
            id: repoID,
            name: name,
            repoURL: url,
            authType: authType,
            platform: SkillRepository.platformFrom(repoURL: url),
            isEnabled: true,
            lastSyncedAt: nil,
            localSlug: SkillRepository.slugFrom(repoURL: url),
            httpUsername: authType.requiresToken ? (username.isEmpty ? nil : username) : nil,
            credentialKey: credentialKey,
            scanHiddenPaths: scanHiddenPaths,
            syncOnLaunch: syncOnLaunch
        )

        do {
            try await skillManager.addRepository(
                repo,
                token: authType.requiresToken ? token : nil
            )
            // Dismiss sheet on success, then trigger initial sync in background
            isPresented = false
            Task { await skillManager.syncRepository(id: repo.id) }
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
        }
    }

    private func chooseLocalImportSelection() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = appLocalized("Choose")
        panel.message = appLocalized("Choose a SKILL.md file or a folder to scan for skills.")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        localSelectionURL = url
        localCandidates = []
        singleFileSkillName = ""
        errorMessage = nil

        Task { await scanLocalSelection(url) }
    }

    private func scanLocalSelection(_ url: URL) async {
        isScanningLocalSelection = true
        defer { isScanningLocalSelection = false }

        do {
            let candidates = try await skillManager.scanLocalImportCandidates(
                at: url,
                includeHiddenPaths: scanHiddenPaths
            )
            localCandidates = candidates
            if let candidate = candidates.first, candidate.requiresCustomName {
                let suggestedName = candidate.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !suggestedName.isEmpty {
                    singleFileSkillName = suggestedName
                }
            }
        } catch {
            localCandidates = []
            errorMessage = error.localizedDescription
        }
    }

    private func importLocalSkills() async {
        let drafts = localImportDrafts()
        guard !drafts.isEmpty else {
            errorMessage = appLocalized("No importable local skills were found.")
            return
        }

        isAdding = true
        errorMessage = nil
        var results: [LocalImportResult] = []

        for (index, draft) in drafts.enumerated() {
            let wasReplacing = skillManager.skills.contains { $0.id == draft.skillName }
            if let existingSkill = skillManager.skills.first(where: { $0.id == draft.skillName }) {
                let resolution = await requestConflictResolution(
                    for: draft,
                    existingSkill: existingSkill
                )

                switch resolution {
                case .skip:
                    results.append(LocalImportResult(
                        draft: draft,
                        status: .skipped,
                        message: appLocalized("Skipped by user.")
                    ))
                    continue
                case .cancelAll:
                    results.append(LocalImportResult(
                        draft: draft,
                        status: .cancelled,
                        message: appLocalized("Cancelled by user.")
                    ))

                    for remainingDraft in drafts.suffix(from: drafts.index(after: index)) {
                        results.append(LocalImportResult(
                            draft: remainingDraft,
                            status: .cancelled,
                            message: appLocalized("Cancelled before import.")
                        ))
                    }

                    importResults = results
                    showImportSummary = true
                    isAdding = false
                    return
                case .replace:
                    break
                }
            }

            do {
                try await skillManager.importLocalSkill(
                    from: draft.candidate.sourceURL,
                    skillName: draft.skillName
                )
                results.append(LocalImportResult(
                    draft: draft,
                    status: wasReplacing ? .replaced : .imported,
                    message: nil
                ))
            } catch {
                results.append(LocalImportResult(
                    draft: draft,
                    status: .failed,
                    message: error.localizedDescription
                ))
            }
        }

        importResults = results
        showImportSummary = true
        isAdding = false
    }

    private func localImportDrafts() -> [LocalImportDraft] {
        localCandidates.compactMap { candidate in
            let resolvedName: String
            if candidate.requiresCustomName {
                resolvedName = singleFileSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                resolvedName = candidate.suggestedSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !resolvedName.isEmpty else { return nil }
            return LocalImportDraft(candidate: candidate, skillName: resolvedName)
        }
    }

    private func requestConflictResolution(
        for draft: LocalImportDraft,
        existingSkill: Skill
    ) async -> LocalImportConflictResolution {
        await withCheckedContinuation { continuation in
            pendingConflict = LocalImportConflict(draft: draft, existingSkill: existingSkill)
            conflictContinuation = continuation
        }
    }

    private func resolveConflict(_ resolution: LocalImportConflictResolution) {
        pendingConflict = nil
        conflictContinuation?.resume(returning: resolution)
        conflictContinuation = nil
    }

    private func candidateDisplayName(_ candidate: LocalSkillImportService.Candidate) -> String {
        let resolvedName = candidate.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolvedName.isEmpty {
            return resolvedName
        }
        return candidate.suggestedSkillName
    }

    /// Keep form values coherent when switching between SSH and HTTPS modes.
    private func applyAuthTypeChange(_ newType: SkillRepository.AuthType) {
        errorMessage = nil

        let converted = SkillRepository.convertRepoURL(repoURL, to: newType)
        if converted != repoURL {
            repoURL = converted
        }

        if newType.requiresToken && httpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            httpUsername = "git"
        }
    }
}

private struct LocalImportSummarySheet: View {
    let results: [AddRepositorySheet.LocalImportResult]
    @Binding var isPresented: Bool

    private var importedCount: Int {
        results.filter { $0.status == .imported || $0.status == .replaced }.count
    }

    private var skippedCount: Int {
        results.filter { $0.status == .skipped }.count
    }

    private var failedCount: Int {
        results.filter { $0.status == .failed }.count
    }

    private var cancelledCount: Int {
        results.filter { $0.status == .cancelled }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appLocalized("Import Summary"))
                .font(.headline)

            Text(
                AppLocalization.format(
                    "Imported %@, skipped %@, failed %@, cancelled %@.",
                    "\(importedCount)",
                    "\(skippedCount)",
                    "\(failedCount)",
                    "\(cancelledCount)"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            List(results) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.status.iconName)
                        .foregroundStyle(result.status.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.draft.skillName)
                            .fontWeight(.medium)
                        Text(result.status.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.draft.candidate.sourceURL.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                        if let message = result.message, !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)

            HStack {
                Spacer()
                Button(appLocalized("Done")) {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 460)
    }
}
