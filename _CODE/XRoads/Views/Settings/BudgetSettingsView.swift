import SwiftUI

// MARK: - BudgetSettingsView

/// Phase 5: Budget control settings — presets, thresholds, throttle, daily limits.
public struct BudgetSettingsView: View {

    @AppStorage("budgetPreset") private var budgetPreset = BudgetPreset.standard.id
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
            ForEach(BudgetPreset.builtin) { preset in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                        Text(preset.description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()

                    Text(BudgetSettingsView.budgetDisplay(for: preset))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)

                    if budgetPreset == preset.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    budgetPreset = preset.id
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
                budgetPreset = BudgetPreset.standard.id
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
        // Daily limit is optional on a preset — preserve user override when nil.
        if let daily = preset.dailyLimitCents {
            dailyLimitCents = daily
        }
    }

    /// Picker-friendly currency label for a preset.
    /// Renders the unlimited sentinel as "∞" to keep the UI honest.
    fileprivate static func budgetDisplay(for preset: BudgetPreset) -> String {
        if preset.id == BudgetPreset.unlimited.id {
            return "∞"
        }
        let dollars = Double(preset.budgetCents) / 100.0
        if dollars >= 1 && dollars.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(dollars))"
        }
        return String(format: "$%.2f", dollars)
    }
}
