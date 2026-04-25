import SwiftUI

// MARK: - ChairmanFeedPanelView

/// Displays the latest Chairman brief from the active CockpitSession.
/// Auto-refreshes when CockpitSession.chairmanBrief changes via @Observable binding.
///
/// US-004: Cockpit UI — chat panel per slot + Chairman feed display
struct ChairmanFeedPanelView: View {
    let chairmanBrief: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.terminalYellow)

                Text("CHAIRMAN BRIEF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if chairmanBrief != nil {
                    Circle()
                        .fill(Color.statusSuccess)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.statusSuccess.opacity(0.6), radius: 3)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)

            Divider()

            // Brief content
            if let brief = chairmanBrief {
                ScrollView {
                    Text(brief)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.textTertiary)
                    Text("No brief yet")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Text("Chairman synthesizes after 5 messages or on blocker")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.borderMuted.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ChairmanFeedPanelView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.md) {
            ChairmanFeedPanelView(chairmanBrief: "## Status\nAll 3 agents active.\n\n## Blockers\n- None\n\n## Action Items\n- Continue feature implementation")
                .frame(height: 200)

            ChairmanFeedPanelView(chairmanBrief: nil)
                .frame(height: 150)
        }
        .padding()
        .background(Color.bgApp)
    }
}
#endif
