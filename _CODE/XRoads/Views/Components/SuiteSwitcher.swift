import SwiftUI

// MARK: - SuiteSwitcher

/// Toolbar-level suite selector. Shows the active suite with its neon color
/// and allows switching via a dropdown menu. Visible in the main toolbar.
struct SuiteSwitcher: View {
    @Environment(\.appState) private var appState
    @State private var isHovering = false

    private var activeSuite: Suite {
        Suite.builtIn.first(where: { $0.id == appState.activeSuiteId }) ?? .developer
    }

    var body: some View {
        Menu {
            ForEach(Suite.builtIn, id: \.id) { suite in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.activeSuiteId = suite.id
                    }
                    // If cockpit is active, notify for live suite switch
                    NotificationCenter.default.post(
                        name: .suiteSwitched,
                        object: nil,
                        userInfo: ["suiteId": suite.id]
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(suite.name)
                            Text("\(suite.roles.count) roles \u{2022} \(suite.phases.count) phases")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: suite.icon)
                    }
                }
                .disabled(suite.id == appState.activeSuiteId)
            }
        } label: {
            HStack(spacing: 6) {
                // Suite icon with neon glow
                Image(systemName: activeSuite.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(activeSuite.accentColor)
                    .shadow(color: activeSuite.accentColor.opacity(0.6), radius: isHovering ? 6 : 3)

                Text(activeSuite.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(activeSuite.accentColor)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(activeSuite.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(activeSuite.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovering = $0 }
    }
}

// MARK: - SuiteGlowBorder

/// A subtle neon glow border around the entire app window based on the active suite.
/// Inspired by ArtDirectorGlowBorder but adapted for suite-level theming.
struct SuiteGlowBorder: View {
    let suite: Suite
    @State private var glowPulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                LinearGradient(
                    colors: [
                        suite.accentColor.opacity(0.6),
                        suite.glowColor.opacity(0.3),
                        suite.accentColor.opacity(0.1),
                        suite.glowColor.opacity(0.3),
                        suite.accentColor.opacity(0.6),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
            .shadow(color: suite.accentColor.opacity(glowPulse ? 0.3 : 0.1), radius: glowPulse ? 12 : 6)
            .shadow(color: suite.glowColor.opacity(glowPulse ? 0.15 : 0.05), radius: glowPulse ? 20 : 10)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
    }
}

// MARK: - SuitePhaseIndicator

/// Compact phase indicator showing the active suite's orchestration phases.
/// Displayed in the toolbar or status area.
struct SuitePhaseIndicator: View {
    let suite: Suite
    var activePhaseId: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(suite.phases, id: \.id) { phase in
                let isActive = phase.id == activePhaseId

                Text(phase.name)
                    .font(.system(size: 7, weight: isActive ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(isActive ? suite.accentColor : Color.textTertiary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        isActive
                            ? suite.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                if phase.id != suite.phases.last?.id {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.textTertiary.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let suiteSwitched = Notification.Name("suiteSwitched")
}
