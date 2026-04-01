import SwiftUI

// MARK: - AdvancedSettingsView

/// Phase 5: Advanced settings — heartbeat config, ML controls, data management.
public struct AdvancedSettingsView: View {

    // Cockpit Brain
    @AppStorage("brainCycleDelaySeconds") private var brainCycleDelay = 60
    @AppStorage("brainMaxCrashRestarts") private var brainMaxCrashRestarts = 3
    @AppStorage("brainMaxTurns") private var brainMaxTurns = 30
    @AppStorage("brainEnabled") private var brainEnabled = true

    // Heartbeat
    @AppStorage("heartbeatIntervalMs") private var heartbeatIntervalMs = 30000
    @AppStorage("heartbeatMaxFailures") private var maxFailures = 5
    @AppStorage("heartbeatEnabled") private var heartbeatEnabled = true

    // ML
    @AppStorage("mlEnabled") private var mlEnabled = true
    @AppStorage("mlAutoTrain") private var mlAutoTrain = true
    @AppStorage("mlMinSamples") private var mlMinSamples = 10

    // Scheduling
    @AppStorage("scheduledRunsEnabled") private var scheduledRunsEnabled = false

    // Config Versioning
    @AppStorage("autoSnapshot") private var autoSnapshot = true

    public init() {}

    public var body: some View {
        Form {
            cockpitBrainSection
            heartbeatSection
            mlSection
            schedulingSection
            configSection
            dangerZoneSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.bgSurface)
        .padding()
    }

    // MARK: - Cockpit Brain

    private var cockpitBrainSection: some View {
        Section {
            Toggle("Enable Cockpit Brain", isOn: $brainEnabled)
                .foregroundStyle(Color.textPrimary)

            if brainEnabled {
                Picker("Cycle Delay (between scans)", selection: $brainCycleDelay) {
                    Text("10s (aggressive)").tag(10)
                    Text("30s (balanced)").tag(30)
                    Text("60s (default)").tag(60)
                    Text("120s (relaxed)").tag(120)
                    Text("300s (minimal)").tag(300)
                }
                .foregroundStyle(Color.textPrimary)

                Stepper("Max Turns per Scan: \(brainMaxTurns)", value: $brainMaxTurns, in: 5...100, step: 5)
                    .foregroundStyle(Color.textPrimary)

                Stepper("Max Crash Restarts: \(brainMaxCrashRestarts)", value: $brainMaxCrashRestarts, in: 1...10)
                    .foregroundStyle(Color.textPrimary)

                Text("Each scan uses up to \(brainMaxTurns) tool calls (git, file reads, etc). Between scans: \(brainCycleDelay)s pause. Crash recovery: \(brainMaxCrashRestarts) attempts.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }
        } header: {
            Label("Cockpit Brain", systemImage: "brain.head.profile")
                .foregroundStyle(Color.textPrimary)
        } footer: {
            Text("The brain is a Claude Code session that monitors dev agents, produces deliverables, and sends status to the chat. It cycles continuously while the session is active.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Heartbeat

    private var heartbeatSection: some View {
        Section {
            Toggle("Enable Heartbeat Monitoring", isOn: $heartbeatEnabled)
                .foregroundStyle(Color.textPrimary)

            if heartbeatEnabled {
                Picker("Pulse Interval", selection: $heartbeatIntervalMs) {
                    Text("5s (aggressive)").tag(5000)
                    Text("15s (balanced)").tag(15000)
                    Text("30s (default)").tag(30000)
                    Text("60s (light)").tag(60000)
                    Text("120s (minimal)").tag(120000)
                }
                .foregroundStyle(Color.textPrimary)

                Stepper("Max Failures: \(maxFailures)", value: $maxFailures, in: 1...20)
                    .foregroundStyle(Color.textPrimary)

                Text("Agent auto-pauses after \(maxFailures) consecutive heartbeat failures")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }
        } header: {
            Label("Heartbeat", systemImage: "heart.text.square")
                .foregroundStyle(Color.textPrimary)
        } footer: {
            Text("Code-aware health checks: git status, test results, story progress, merge readiness")
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Machine Learning

    private var mlSection: some View {
        Section {
            Toggle("Enable On-Device ML", isOn: $mlEnabled)
                .foregroundStyle(Color.textPrimary)

            if mlEnabled {
                Toggle("Auto-Train After Orchestration", isOn: $mlAutoTrain)
                    .foregroundStyle(Color.textPrimary)

                Stepper("Min Samples: \(mlMinSamples)", value: $mlMinSamples, in: 5...50, step: 5)
                    .foregroundStyle(Color.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Models")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)

                    mlModelRow(name: "LinearRegression", purpose: "Story time estimation", icon: "clock")
                    mlModelRow(name: "NaiveBayes", purpose: "Story categorization", icon: "tag")
                    mlModelRow(name: "DecisionTree", purpose: "Conflict prediction", icon: "exclamationmark.triangle")
                }
                .padding(.vertical, 4)

                Button {
                    // Trigger retrain
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retrain Models Now")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(Color.accentPrimary)
            }
        } header: {
            Label("Machine Learning", systemImage: "brain")
                .foregroundStyle(Color.textPrimary)
        } footer: {
            Text("Models train locally from your orchestration history. No data leaves your machine.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func mlModelRow(name: String, purpose: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 16)

            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text(purpose)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Scheduling

    private var schedulingSection: some View {
        Section {
            Toggle("Enable Scheduled Runs", isOn: $scheduledRunsEnabled)
                .foregroundStyle(Color.textPrimary)

            if scheduledRunsEnabled {
                ScheduleManagerView()
                    .frame(minHeight: 200)
            }
        } header: {
            Label("Autonomous Scheduling", systemImage: "calendar.badge.clock")
                .foregroundStyle(Color.textPrimary)
        } footer: {
            Text("Run orchestrations on a cron schedule or trigger on git push / PRD changes")
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Config Versioning

    private var configSection: some View {
        Section {
            Toggle("Auto-Snapshot on Config Change", isOn: $autoSnapshot)
                .foregroundStyle(Color.textPrimary)

            if autoSnapshot {
                ConfigHistoryView()
                    .frame(minHeight: 200)
            }
        } header: {
            Label("Config Versioning", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                resetAdvancedToDefaults()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Advanced Settings to Defaults")
                }
            }
            .foregroundStyle(Color.statusError)

            Button(role: .destructive) {
                // Clear ML models
                let mlDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".crossroads/ml")
                try? FileManager.default.removeItem(at: mlDir)
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Trained ML Models")
                }
            }
            .foregroundStyle(Color.statusError)
        } header: {
            Label("Danger Zone", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.statusError)
        }
    }

    private func resetAdvancedToDefaults() {
        brainCycleDelay = 60
        brainMaxCrashRestarts = 3
        brainMaxTurns = 30
        brainEnabled = true
        heartbeatIntervalMs = 30000
        maxFailures = 5
        heartbeatEnabled = true
        mlEnabled = true
        mlAutoTrain = true
        mlMinSamples = 10
        scheduledRunsEnabled = false
        autoSnapshot = true
    }
}
