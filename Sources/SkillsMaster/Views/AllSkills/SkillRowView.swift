import SwiftUI

/// SkillRowView is the skill card for each row in the list
///
/// Displays skill name, description, scope badge, and installed Agent icons
struct SkillRowView: View {

    let skill: Skill

    /// Get SkillManager from environment for reading updateStatuses dictionary
    /// @Environment is SwiftUI's dependency injection mechanism (similar to Spring's @Autowired)
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: name + scope + update indicator (always single line, name has priority)
            HStack(spacing: 6) {
                Text(skill.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                ScopeBadge(scope: skill.scope)
                    .layoutPriority(0)
                    .fixedSize()

                // F12: Display different indicator icons based on update check status
                updateStatusIndicator
                    .fixedSize()

                Spacer(minLength: 0)
            }

            // Second row: description (max 2 lines)
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Third row: author + version + source
            HStack(spacing: 12) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let version = skill.metadata.version {
                    Label(version, systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lockEntry = skill.lockEntry {
                    Label(lockEntry.source, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Fourth row: installed Agent icons.
            // Wraps onto multiple lines when there are many installations and the
            // available width is small, so the skill name above always stays visible.
            // Direct installations: full opacity
            // Inherited installations (cross-read access only): heavily de-emphasized
            if !skill.installations.isEmpty {
                AgentIconWrapView(installations: skill.installations)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Update Status Indicator

    /// Renders different status indicators based on SkillUpdateStatus enum
    ///
    /// @ViewBuilder allows using conditional branches in computed properties to return different View types,
    /// the compiler automatically wraps them into concrete types of `some View` (similar to Java generics type erasure but resolved at compile time).
    /// Uses `switch` to exhaustively enumerate all enum cases (Swift enforces exhaustive matching, similar to Rust's match).
    @ViewBuilder
    private var updateStatusIndicator: some View {
        switch skillManager.updateStatuses[skill.id] ?? .notChecked {
        case .notChecked:
            // Default state: display nothing
            // EmptyView() is SwiftUI's empty view placeholder, takes no space
            EmptyView()
        case .checking:
            // Checking: display spinning progress indicator (ProgressView)
            // .controlSize(.mini) makes spinner smaller, suitable for inline display
            ProgressView()
                .controlSize(.mini)
        case .hasUpdate:
            // 有可用更新: orange up arrow in filled circle icon
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .help(AppLocalization.string("Update available"))
        case .upToDate:
            // 已是最新: green checkmark in filled circle icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help(AppLocalization.string("Up to Date"))
        case .error(let message):
            // 检查失败：yellow warning triangle icon, hover shows error details
            // .help() sets mouse hover tooltip (native macOS feature)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .help(AppLocalization.format("Check failed: %@", message))
        }
    }
}

/// Lays out a row of `AgentIconView`s that wraps onto multiple lines when the
/// available width is too small to fit them all on one line. Used in
/// `SkillRowView` so that long agent installation lists never compress the skill
/// name above into truncation.
private struct AgentIconWrapView: View {

    let installations: [SkillInstallation]

    private let iconSize: CGFloat = 12
    private let spacing: CGFloat = 4

    var body: some View {
        WrapLayout(spacing: spacing) {
            ForEach(installations) { installation in
                Group {
                    if installation.isInherited {
                        AgentIconView(agentType: installation.agentType, size: iconSize)
                            .opacity(0.22)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        Color.secondary.opacity(0.35),
                                        style: StrokeStyle(lineWidth: 0.5, dash: [1.5, 1.5])
                                    )
                            )
                    } else {
                        AgentIconView(agentType: installation.agentType, size: iconSize)
                    }
                }
                .help(installation.isInherited
                    ? AppLocalization.format(
                        "%@ can read from %@ (not directly installed)",
                        installation.agentType.displayName,
                        installation.parentDirectoryDisplayPath)
                    : installation.agentType.displayName)
            }
        }
    }
}

/// A simple wrapping (flow) layout: arranges subviews left-to-right, wrapping to
/// the next line when the proposed width is exhausted. Each subview is laid out
/// at its ideal size.
private struct WrapLayout: Layout {

    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                // Wrap
                totalWidth = max(totalWidth, x - spacing)
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, x - spacing)
        let totalHeight = y + rowHeight
        return CGSize(width: max(0, totalWidth), height: max(0, totalHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                // Wrap to next row
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
