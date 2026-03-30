import SwiftUI

// MARK: - ConfigHistoryView

/// Config version history and rollback interface.
/// Shows ConfigSnapshots ordered by version (newest first) with diff viewing.
public struct ConfigHistoryView: View {

    @State private var snapshots: [ConfigSnapshot] = []
    @State private var selectedSnapshot: ConfigSnapshot?
    @State private var showDiffSheet: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var filterConfigType: String = "all"

    /// Session ID to filter snapshots (nil shows all)
    let sessionId: UUID?
    let configSnapshotRepository: ConfigSnapshotRepository?

    init(sessionId: UUID? = nil, configSnapshotRepository: ConfigSnapshotRepository? = nil) {
        self.sessionId = sessionId
        self.configSnapshotRepository = configSnapshotRepository
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .background(Color.borderMuted)

            // Content
            if isLoading {
                loadingView
            } else if snapshots.isEmpty {
                emptyState
            } else {
                snapshotList
            }
        }
        .background(Color.bgSurface)
        .task {
            await loadSnapshots()
        }
        .sheet(isPresented: $showDiffSheet) {
            if let snapshot = selectedSnapshot {
                ConfigDiffSheet(snapshot: snapshot, onDismiss: { showDiffSheet = false })
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Config History", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text("\(snapshots.count) versions")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            Button {
                Task { await loadSnapshots() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Snapshot List

    private var snapshotList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(snapshots) { snapshot in
                    SnapshotRow(
                        snapshot: snapshot,
                        onViewDiff: {
                            selectedSnapshot = snapshot
                            showDiffSheet = true
                        },
                        onRollback: {
                            rollback(to: snapshot)
                        }
                    )
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    // MARK: - Empty & Loading

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Loading snapshots...")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.textTertiary)

            Text("No Config Snapshots")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textSecondary)

            Text("Config changes will appear here\nwhen auto-snapshot is enabled.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadSnapshots() async {
        guard let repo = configSnapshotRepository, let sid = sessionId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Fetch for common config types
            let configTypes = ["budget", "heartbeat", "roles", "schedule", "general"]
            var all: [ConfigSnapshot] = []
            for ct in configTypes {
                let batch = try await repo.fetchSnapshots(sessionId: sid, configType: ct)
                all.append(contentsOf: batch)
            }
            snapshots = all.sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rollback(to snapshot: ConfigSnapshot) {
        guard let repo = configSnapshotRepository else { return }
        Task {
            do {
                // Create a new snapshot that reverts to this version's data
                var rollbackSnapshot = ConfigSnapshot(
                    sessionId: snapshot.sessionId,
                    workspaceId: snapshot.workspaceId,
                    configType: snapshot.configType,
                    version: 0, // auto-calculated by repo
                    data: snapshot.data,
                    changedBy: "user",
                    changeReason: "Rollback to version \(snapshot.version)"
                )
                _ = try await repo.createSnapshot(rollbackSnapshot)
                await loadSnapshots()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - SnapshotRow

private struct SnapshotRow: View {
    let snapshot: ConfigSnapshot
    let onViewDiff: () -> Void
    let onRollback: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Version number
            Text("v\(snapshot.version)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 32)

            // Config type badge
            Text(snapshot.configType)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.bgElevated)
                .clipShape(Capsule())

            // Changed by + reason
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.changedBy)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                if let reason = snapshot.changeReason {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Timestamp
            Text(snapshot.createdAt, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)

            // Diff button
            if snapshot.diff != nil {
                Button {
                    onViewDiff()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("View diff")
            }

            // Rollback button
            Button {
                onRollback()
            } label: {
                Text("Rollback")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.statusWarning)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color.bgCanvas)
        .cornerRadius(Theme.Radius.sm)
    }
}

// MARK: - ConfigDiffSheet

private struct ConfigDiffSheet: View {
    let snapshot: ConfigSnapshot
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header
            HStack {
                Text("Config Diff — v\(snapshot.version)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(snapshot.configType)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.bgElevated)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Diff content
            ScrollView {
                if let diff = snapshot.diff, !diff.isEmpty {
                    Text(diff)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Show full data if no diff available
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Full Config Data:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)

                        Text(formatJSON(snapshot.data))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 500, minHeight: 350)
        .background(Color.bgSurface)
    }

    private func formatJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return jsonString
        }
        return result
    }
}

// MARK: - Preview

#if DEBUG
struct ConfigHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigHistoryView(sessionId: UUID())
            .frame(width: 550, height: 400)
            .background(Color.bgApp)
    }
}
#endif
