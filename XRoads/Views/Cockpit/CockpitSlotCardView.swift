import SwiftUI

// MARK: - CockpitSlotCardView

/// Displays a single agent slot card within the Cockpit Mode panel.
/// Shows: skill name, agent type, status badge, and current task.
struct CockpitSlotCardView: View {
    let slot: AgentSlot
    let skillName: String
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header: slot index + agent type + status
            HStack {
                // Slot index badge
                Text("#\(slot.slotIndex)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.bgApp)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))

                // Skill name
                Text(skillName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Status badge
                cockpitStatusBadge
            }

            // Agent type
            HStack(spacing: 4) {
                Image(systemName: agentIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentPrimary)
                Text(slot.agentType)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            // Branch name (if assigned)
            if let branch = slot.branchName {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                    Text(branch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(statusBorderColor.opacity(0.4), lineWidth: 1)
        )
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : 20)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isRevealed)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var cockpitStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.6), radius: 3)

            Text(statusLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var agentIcon: String {
        switch slot.agentType.lowercased() {
        case "claude": return "brain.head.profile"
        case "gemini": return "sparkles"
        case "codex": return "terminal"
        default: return "cpu"
        }
    }

    private var statusColor: Color {
        switch slot.status {
        case .empty: return Color.textTertiary
        case .provisioning: return Color.statusInfo
        case .running: return Color.statusSuccess
        case .waitingApproval: return Color.statusWarning
        case .paused: return Color.terminalYellow
        case .done: return Color.accentPrimary
        case .error: return Color.statusError
        }
    }

    private var statusBorderColor: Color {
        switch slot.status {
        case .running: return Color.statusSuccess
        case .error: return Color.statusError
        case .waitingApproval: return Color.statusWarning
        default: return Color.borderMuted
        }
    }

    private var statusLabel: String {
        switch slot.status {
        case .empty: return "EMPTY"
        case .provisioning: return "PROVISIONING"
        case .running: return "RUNNING"
        case .waitingApproval: return "APPROVAL"
        case .paused: return "PAUSED"
        case .done: return "DONE"
        case .error: return "ERROR"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CockpitSlotCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.sm) {
            CockpitSlotCardView(
                slot: AgentSlot(
                    cockpitSessionId: UUID(),
                    slotIndex: 0,
                    status: .running,
                    agentType: "claude",
                    branchName: "feat/api"
                ),
                skillName: "backend-dev",
                isRevealed: true
            )
            CockpitSlotCardView(
                slot: AgentSlot(
                    cockpitSessionId: UUID(),
                    slotIndex: 1,
                    status: .paused,
                    agentType: "gemini",
                    branchName: "feat/ui"
                ),
                skillName: "frontend-dev",
                isRevealed: true
            )
        }
        .padding()
        .background(Color.bgApp)
    }
}
#endif
