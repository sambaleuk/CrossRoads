import SwiftUI

// MARK: - ScheduleManagerView

/// Manage scheduled orchestration runs.
/// Shows list with enable/disable toggle, trigger type badges, and add/run controls.
public struct ScheduleManagerView: View {

    @State private var scheduledRuns: [ScheduledRun] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showAddSheet: Bool = false

    let heartbeatRepository: HeartbeatRepository?

    init(heartbeatRepository: HeartbeatRepository? = nil) {
        self.heartbeatRepository = heartbeatRepository
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(Color.borderMuted)

            if isLoading {
                loadingView
            } else if scheduledRuns.isEmpty {
                emptyState
            } else {
                scheduleList
            }
        }
        .background(Color.bgSurface)
        .task {
            await loadSchedules()
        }
        .sheet(isPresented: $showAddSheet) {
            AddScheduleSheet(
                heartbeatRepository: heartbeatRepository,
                onCreated: {
                    Task { await loadSchedules() }
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Scheduled Runs", systemImage: "calendar.badge.clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text("\(scheduledRuns.count) schedules")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentPrimary)
            }
            .buttonStyle(.plain)
            .help("Add Schedule")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Schedule List

    private var scheduleList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(scheduledRuns) { run in
                    ScheduleRunRow(
                        run: run,
                        onToggle: { toggleRun(run) },
                        onRunNow: { runNow(run) }
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
            ProgressView().controlSize(.small)
            Text("Loading schedules...")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(Color.textTertiary)

            Text("No Scheduled Runs")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textSecondary)

            Text("Add a schedule to run orchestrations\nautomatically on a cron or trigger.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Add Schedule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentPrimary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadSchedules() async {
        guard let repo = heartbeatRepository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            scheduledRuns = try await repo.fetchAllScheduledRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRun(_ run: ScheduledRun) {
        guard let repo = heartbeatRepository else { return }
        Task {
            do {
                try await repo.toggleScheduledRun(id: run.id, enabled: !run.enabled)
                await loadSchedules()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runNow(_ run: ScheduledRun) {
        guard let repo = heartbeatRepository else { return }
        Task {
            do {
                try await repo.updateRunResult(id: run.id, result: "triggered_manually", nextRunAt: run.nextRunAt)
                await loadSchedules()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - ScheduleRunRow

private struct ScheduleRunRow: View {
    let run: ScheduledRun
    let onToggle: () -> Void
    let onRunNow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { run.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            // Trigger type badge
            triggerBadge

            // Details
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: run.prdPath).lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.sm) {
                    if let cron = run.cronExpression {
                        Text(cron)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.terminalCyan)
                    }

                    if let next = run.nextRunAt {
                        Text("Next: \(next, style: .relative)")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            // Last result
            if let result = run.lastRunResult {
                Text(result)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(resultColor(result))
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }

            // Run Now button
            Button {
                onRunNow()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.statusSuccess)
            }
            .buttonStyle(.plain)
            .help("Run Now")
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color.bgCanvas)
        .cornerRadius(Theme.Radius.sm)
        .opacity(run.enabled ? 1.0 : 0.6)
    }

    private var triggerBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: triggerIcon)
                .font(.system(size: 8))
            Text(run.triggerType)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(triggerColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(triggerColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var triggerIcon: String {
        switch run.triggerType {
        case "cron": return "clock"
        case "manual": return "hand.tap"
        case "git_push": return "arrow.triangle.branch"
        default: return "bolt"
        }
    }

    private var triggerColor: Color {
        switch run.triggerType {
        case "cron": return .statusInfo
        case "manual": return .textSecondary
        case "git_push": return .statusSuccess
        default: return .textTertiary
        }
    }

    private func resultColor(_ result: String) -> Color {
        if result.contains("success") || result.contains("completed") {
            return .statusSuccess
        } else if result.contains("fail") || result.contains("error") {
            return .statusError
        } else {
            return .textTertiary
        }
    }
}

// MARK: - AddScheduleSheet

private struct AddScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let heartbeatRepository: HeartbeatRepository?
    let onCreated: () -> Void

    @State private var triggerType: String = "cron"
    @State private var cronExpression: String = "0 */6 * * *"
    @State private var prdPath: String = ""
    @State private var projectPath: String = ""
    @State private var budgetPreset: String = "Standard"
    @State private var errorMessage: String?

    private let cronPresets: [(String, String)] = [
        ("Every 6 hours", "0 */6 * * *"),
        ("Every day at 9am", "0 9 * * *"),
        ("Every Monday", "0 9 * * 1"),
        ("Every hour", "0 * * * *"),
        ("Every 15 minutes", "*/15 * * * *"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Header
            HStack {
                Text("Add Scheduled Run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Trigger type
            Picker("Trigger Type", selection: $triggerType) {
                Text("Cron").tag("cron")
                Text("Manual").tag("manual")
                Text("Git Push").tag("git_push")
            }
            .pickerStyle(.segmented)

            // Cron expression
            if triggerType == "cron" {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Cron Expression")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)

                    TextField("0 */6 * * *", text: $cronExpression)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    // Presets
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(cronPresets, id: \.1) { preset in
                            Button {
                                cronExpression = preset.1
                            } label: {
                                Text(preset.0)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }

            // PRD Path
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("PRD Path")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                TextField("/path/to/prd.json", text: $prdPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            // Project Path
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Project Path")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                TextField("/path/to/project", text: $projectPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            // Budget Preset
            Picker("Budget Preset", selection: $budgetPreset) {
                Text("Frugal").tag("Frugal")
                Text("Standard").tag("Standard")
                Text("Performance").tag("Performance")
                Text("Unlimited").tag("Unlimited")
            }
            .foregroundStyle(Color.textPrimary)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.statusError)
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Create Schedule") {
                    createSchedule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(prdPath.isEmpty || projectPath.isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 450, height: 480)
        .background(Color.bgSurface)
    }

    private func createSchedule() {
        guard let repo = heartbeatRepository else {
            errorMessage = "Repository not available"
            return
        }

        let run = ScheduledRun(
            projectPath: projectPath,
            prdPath: prdPath,
            cronExpression: triggerType == "cron" ? cronExpression : nil,
            triggerType: triggerType,
            budgetPreset: budgetPreset,
            enabled: true
        )

        Task {
            do {
                _ = try await repo.createScheduledRun(run)
                onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ScheduleManagerView_Previews: PreviewProvider {
    static var previews: some View {
        ScheduleManagerView()
            .frame(width: 550, height: 400)
            .background(Color.bgApp)
    }
}
#endif
