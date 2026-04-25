import SwiftUI

// MARK: - BudgetSettingsView

/// Phase 5: Budget control settings — presets, thresholds, throttle, daily limits.
public struct BudgetSettingsView: View {

    @AppStorage("budgetPreset") private var budgetPreset = "Standard"
    @AppStorage("budgetWarningPct") private var warningPct = 80
    @AppStorage("budgetHardStop") private var hardStop = true
    @AppStorage("budgetThrottle") private var throttle = true
    @AppStorage("budgetDailyLimitCents") private var dailyLimitCents = 0
    @AppStorage("budgetPerStoryLimitCents") private var perStoryLimitCents = 0

    public init() {}

    public var body: some View {
        Form {
            // Preset selector
            presetSection

            // Thresholds
            thresholdSection

            // Daily / Per-story limits
            limitsSection

            // Reset
            resetSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.bgSurface)
        .padding()
    }

    // MARK: - Presets

    private var presetSection: some View {
        Section {
            ForEach(BudgetPreset.allCases, id: \.self) { preset in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                        Text(preset.description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()

                    Text(preset.budgetDisplay)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)

                    if budgetPreset == preset.rawValue {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    budgetPreset = preset.rawValue
                    applyPreset(preset)
                }
            }
        } header: {
            Label("Budget Preset", systemImage: "dollarsign.circle")
                .foregroundStyle(Color.textPrimary)
        } footer: {
            Text("Presets configure default budget caps for new sessions")
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Thresholds

    private var thresholdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Warning Threshold")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(warningPct)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.statusWarning)
                }
                Slider(value: Binding(
                    get: { Double(warningPct) },
                    set: { warningPct = Int($0) }
                ), in: 50...95, step: 5)
                .tint(Color.statusWarning)
            }

            Toggle("Hard Stop at 100%", isOn: $hardStop)
                .foregroundStyle(Color.textPrimary)

            if hardStop {
                Text("Agent will be auto-paused when budget is exhausted")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.leading, 20)
            }

            Toggle("Auto-Throttle at Warning", isOn: $throttle)
                .foregroundStyle(Color.textPrimary)

            if throttle {
                Text("Reduces agent request frequency when approaching budget limit")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.leading, 20)
            }
        } header: {
            Label("Thresholds & Behavior", systemImage: "gauge.with.needle")
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Limits

    private var limitsSection: some View {
        Section {
            HStack {
                Text("Daily Limit")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                TextField("0 = none", value: $dailyLimitCents, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Text("¢")
                    .foregroundStyle(Color.textTertiary)
            }

            HStack {
                Text("Per-Story Limit")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                TextField("0 = none", value: $perStoryLimitCents, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Text("¢")
                    .foregroundStyle(Color.textTertiary)
            }
        } header: {
            Label("Spending Limits", systemImage: "chart.bar.xaxis")
                .foregroundStyle(Color.textPrimary)
        } footer: {
            Text("Set to 0 to disable. Limits apply per-session.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                applyPreset(.standard)
                budgetPreset = "Standard"
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Budget Settings to Defaults")
                }
            }
            .foregroundStyle(Color.statusError)
        }
    }

    // MARK: - Helpers

    private func applyPreset(_ preset: BudgetPreset) {
        warningPct = preset.warningPct
        hardStop = preset.hardStop
        throttle = preset.throttle
    }
}

// MARK: - BudgetPreset

enum BudgetPreset: String, CaseIterable {
    case frugal = "Frugal"
    case standard = "Standard"
    case performance = "Performance"
    case unlimited = "Unlimited"

    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .frugal: return "Sonnet-only recommended, tight caps"
        case .standard: return "Mixed models, balanced spending"
        case .performance: return "Opus allowed, generous caps"
        case .unlimited: return "No caps, monitoring only"
        }
    }

    var budgetDisplay: String {
        switch self {
        case .frugal: return "$5"
        case .standard: return "$25"
        case .performance: return "$100"
        case .unlimited: return "∞"
        }
    }

    var warningPct: Int {
        switch self {
        case .frugal: return 70
        case .standard: return 80
        case .performance: return 85
        case .unlimited: return 95
        }
    }

    var hardStop: Bool { self != .unlimited }
    var throttle: Bool { self != .unlimited }
}
