import SwiftUI

// MARK: - HeartbeatPanelView

/// Compact heartbeat status display for the cockpit sidebar.
/// Shows per-slot health dots, git changes count, and test pass/fail badges.
///
/// Phase 5: Heartbeat monitoring integration into Cockpit sidebar.
struct HeartbeatPanelView: View {
    let heartbeatResults: [UUID: PulseResult]
    let slots: [AgentSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.statusError)

                Text("HEARTBEAT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                // Summary: alive count
                let aliveCount = heartbeatResults.values.filter(\.alive).count
                let totalCount = heartbeatResults.count
                if totalCount > 0 {
                    Text("\(aliveCount)/\(totalCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(aliveCount == totalCount ? Color.statusSuccess : Color.statusWarning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.bgApp)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)

            Divider()

            // Slot heartbeats
            if heartbeatResults.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    Spacer()
                    Text("No pulse data")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(slots, id: \.id) { slot in
                            if let pulse = heartbeatResults[slot.id] {
                                slotPulseRow(slot: slot, pulse: pulse)
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
            }
        }
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.borderMuted.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Slot Pulse Row

    @ViewBuilder
    private func slotPulseRow(slot: AgentSlot, pulse: PulseResult) -> some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(pulseColor(pulse))
                .frame(width: 6, height: 6)
                .shadow(color: pulseColor(pulse).opacity(0.6), radius: 2)

            // Slot index
            Text("#\(slot.slotIndex)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20, alignment: .leading)

            // Git changes badge
            if pulse.gitChanges > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 7))
                    Text("\(pulse.gitChanges)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.accentPrimary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentPrimary.opacity(0.1))
                .clipShape(Capsule())
            }

            // Tests badge
            if pulse.testsPassed > 0 || pulse.testsFailed > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.statusSuccess)
                    Text("\(pulse.testsPassed)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.statusSuccess)

                    if pulse.testsFailed > 0 {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.statusError)
                        Text("\(pulse.testsFailed)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.statusError)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.bgApp)
                .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func pulseColor(_ pulse: PulseResult) -> Color {
        if !pulse.alive {
            return Color.statusError
        }
        if pulse.testsFailed > 0 || !pulse.errors.isEmpty {
            return Color.statusWarning
        }
        return Color.statusSuccess
    }
}

// MARK: - Preview

#if DEBUG
struct HeartbeatPanelView_Previews: PreviewProvider {
    static var previews: some View {
        Text("HeartbeatPanelView requires PulseResult data for preview")
            .foregroundStyle(Color.textTertiary)
            .frame(width: 280, height: 150)
            .background(Color.bgApp)
    }
}
#endif
