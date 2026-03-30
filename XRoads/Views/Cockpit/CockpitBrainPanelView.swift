import SwiftUI

// MARK: - BrainEntryType (PRD-S09 US-008)

/// Categorizes cockpit brain output for visual styling.
enum BrainEntryType: String, Sendable {
    case thinking
    case action
    case decision
    case loop
    case subagent
    case error

    init(from string: String) {
        self = BrainEntryType(rawValue: string) ?? .thinking
    }
}

// MARK: - BrainEntry (PRD-S09 US-008)

/// A single entry in the cockpit brain consciousness stream.
struct BrainEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let type: BrainEntryType
    let content: String
}

// MARK: - CockpitBrainPanelView

/// PRD-S09 US-008: Live cockpit brain consciousness stream.
///
/// Replaces the static COP display with a LIVING feed of the cockpit brain's
/// Claude Code session output. Shows thinking, actions, decisions, loop pulses,
/// subagent spawns, and errors with distinct visual styling.
///
/// Falls back to static COP display when no brain session is active.
struct CockpitBrainPanelView: View {
    let cop: CockpitOrchestrationPlan?
    let adaptationActions: [AdaptationAction]

    @State private var entries: [BrainEntry] = []
    @State private var isAlive: Bool = false
    @State private var scrollProxy: ScrollViewProxy?

    /// Maximum entries before FIFO eviction
    private let maxEntries = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView

            Divider()

            // Content: live stream or static fallback
            if isAlive || !entries.isEmpty {
                liveStreamView
            } else if let cop = cop {
                staticCOPView(cop)
                    .padding(Theme.Spacing.sm)
            } else {
                emptyStateView
            }
        }
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.borderMuted.opacity(0.4), lineWidth: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: .cockpitBrainOutput)) { notification in
            handleBrainOutput(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cockpitBrainStarted)) { _ in
            isAlive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cockpitBrainStopped)) { _ in
            isAlive = false
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10))
                .foregroundStyle(Color.terminalCyan)

            Text("BRAIN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            // Status dot: green = alive, gray = stopped
            Circle()
                .fill(isAlive ? Color.statusSuccess : Color.textTertiary)
                .frame(width: 6, height: 6)
                .shadow(color: isAlive ? Color.statusSuccess.opacity(0.6) : .clear, radius: 2)

            Text(isAlive ? "consciousness stream" : "offline")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            Spacer()

            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.bgSurface)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color.bgSurface)
    }

    // MARK: - Live Stream

    private var liveStreamView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        brainEntryRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .frame(maxHeight: 300)
            .onChange(of: entries.count) { _, _ in
                // Auto-scroll to newest entry
                if let lastEntry = entries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Brain Entry Row

    @ViewBuilder
    private func brainEntryRow(_ entry: BrainEntry) -> some View {
        switch entry.type {
        case .thinking:
            thinkingRow(entry)
        case .action:
            actionRow(entry)
        case .decision:
            decisionRow(entry)
        case .loop:
            loopRow(entry)
        case .subagent:
            subagentRow(entry)
        case .error:
            errorRow(entry)
        }
    }

    /// Thinking: dimmed italic text (gray)
    private func thinkingRow(_ entry: BrainEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            timestampLabel(entry.timestamp)

            Text(entry.content)
                .font(.system(size: 9, design: .monospaced))
                .italic()
                .foregroundStyle(Color.textTertiary)
                .lineLimit(3)
        }
        .padding(.vertical, 1)
    }

    /// Action: colored badge [Read] [Bash] with content (blue)
    private func actionRow(_ entry: BrainEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            timestampLabel(entry.timestamp)

            // Extract tool name from content (first word)
            let parts = entry.content.split(separator: " ", maxSplits: 1)
            let toolName = parts.first.map(String.init) ?? "tool"
            let detail = parts.count > 1 ? String(parts[1]) : ""

            Text("[\(toolName)]")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.statusInfo)

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }

    /// Decision: highlighted with green left border
    private func decisionRow(_ entry: BrainEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.statusSuccess)
                .frame(width: 2)

            timestampLabel(entry.timestamp)

            Text(entry.content)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.statusSuccess)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    /// Loop: subtle pulse dot with timestamp (gray)
    private func loopRow(_ entry: BrainEntry) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.textTertiary.opacity(0.5))
                .frame(width: 4, height: 4)

            timestampLabel(entry.timestamp)

            Text(entry.content)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Color.textTertiary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }

    /// Subagent: agent name badge (purple)
    private func subagentRow(_ entry: BrainEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            timestampLabel(entry.timestamp)

            Image(systemName: "person.2.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.terminalMagenta)

            Text(entry.content)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.terminalMagenta)
                .lineLimit(2)
        }
        .padding(.vertical, 1)
    }

    /// Error: red text
    private func errorRow(_ entry: BrainEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            timestampLabel(entry.timestamp)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.statusError)

            Text(entry.content)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.statusError)
                .lineLimit(3)
        }
        .padding(.vertical, 1)
    }

    /// Timestamp label in [HH:mm:ss] format
    private func timestampLabel(_ date: Date) -> some View {
        Text(formatTime(date))
            .font(.system(size: 7, design: .monospaced))
            .foregroundStyle(Color.textTertiary.opacity(0.5))
    }

    // MARK: - Static COP Fallback

    @ViewBuilder
    private func staticCOPView(_ cop: CockpitOrchestrationPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Project info
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("PROJECT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)

                Text(cop.projectName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    badgeView(text: cop.projectType, color: Color.statusInfo)
                    badgeView(text: cop.domain, color: Color.terminalMagenta)
                    badgeView(text: cop.marketContext, color: Color.terminalYellow)
                }
            }

            Divider()

            // Waiting for brain message
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)

                Text("Brain session not started")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }

            // Adaptation actions
            if !adaptationActions.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("ADAPTATIONS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)

                    ForEach(Array(adaptationActions.prefix(5).enumerated()), id: \.offset) { _, action in
                        HStack(spacing: 4) {
                            Image(systemName: adaptationIcon(action.action))
                                .font(.system(size: 7))
                                .foregroundStyle(adaptationColor(action.action))

                            Text(action.action.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Spacer()
            Text("No orchestration plan")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }

    // MARK: - Event Handling

    private func handleBrainOutput(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeStr = info["type"] as? String,
              let content = info["content"] as? String,
              let timestamp = info["timestamp"] as? Date
        else { return }

        let entry = BrainEntry(
            timestamp: timestamp,
            type: BrainEntryType(from: typeStr),
            content: content
        )

        entries.append(entry)

        // FIFO eviction
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func badgeView(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func adaptationIcon(_ action: String) -> String {
        switch action {
        case "focus_debugging": return "ladybug.fill"
        case "switch_model": return "arrow.triangle.2.circlepath"
        case "activate_transverse": return "play.fill"
        case "pause_and_resolve": return "pause.fill"
        case "restart_stalled": return "arrow.clockwise"
        default: return "circle.fill"
        }
    }

    private func adaptationColor(_ action: String) -> Color {
        switch action {
        case "focus_debugging": return Color.statusError
        case "switch_model": return Color.statusWarning
        case "activate_transverse": return Color.statusSuccess
        case "pause_and_resolve": return Color.terminalYellow
        case "restart_stalled": return Color.statusInfo
        default: return Color.textTertiary
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CockpitBrainPanelView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.md) {
            CockpitBrainPanelView(
                cop: CockpitOrchestrationPlan(
                    projectName: "my-saas",
                    projectType: "saas",
                    domain: "fintech",
                    marketContext: "competitive",
                    transverseProductions: [
                        TransverseCategory(
                            category: "documentation",
                            deliverables: ["README", "deploy-guide", "changelog"],
                            priority: "high"
                        ),
                    ],
                    specialistTriggers: [],
                    metaAgentConfig: MetaAgentConfig(
                        capabilities: ["qa", "doc_gen", "git_master"],
                        monitoringIntervalMs: 30_000,
                        autonomyLevel: "full"
                    ),
                    deliverablesPath: "/tmp/d/",
                    createdAt: "2026-03-29T00:00:00Z"
                ),
                adaptationActions: [
                    AdaptationAction(action: "activate_transverse", targetSlot: nil, reason: "Coding 75% done"),
                ]
            )

            CockpitBrainPanelView(cop: nil, adaptationActions: [])
        }
        .frame(width: 280)
        .padding()
        .background(Color.bgApp)
    }
}
#endif
