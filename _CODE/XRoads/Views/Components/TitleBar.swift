import SwiftUI

// MARK: - TitleBar

/// 30pt window chrome. Traffic lights remain native (rendered by AppKit on top).
/// Left: brand mark placeholder + wordmark. Right: suite switcher + toolbar icons.
struct TitleBar: View {
    @Binding var showChatPanel: Bool
    @Binding var showInspector: Bool

    let showCockpitPanel: Bool
    let pendingProposalCount: Int

    let onToggleChat: () -> Void
    let onToggleCockpit: () -> Void
    let onToggleReview: () -> Void
    let onStartSession: () -> Void
    let onLoadPRD: () -> Void
    let onShowHistory: () -> Void
    let onShowIntelligence: () -> Void
    let onShowSkills: () -> Void
    let onShowArtDirection: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Traffic-light clearance: AppKit renders the 3 lights at x ≈ 13/33/53pt.
            // 90pt gives ~25pt breathing room from the rightmost light.
            Spacer().frame(width: 90)

            BrandMarkPlaceholder(size: 18)
                .padding(.trailing, 10)

            Text("xroads")
                .font(Theme.TextStyle.bodyLarge)
                .foregroundStyle(Theme.Color.ink)

            Spacer()

            // Right edge
            HStack(spacing: 2) {
                TitleBarSuiteSwitcher()

                titleBarSeparator

                TitleBarButton(
                    systemImage: "sidebar.leading",
                    label: "ORC",
                    active: showChatPanel,
                    help: "Toggle orchestrator chat panel",
                    action: onToggleChat
                )
                .keyboardShortcut("o", modifiers: [.command, .shift])

                TitleBarButton(
                    systemImage: "gauge.open.with.lines.needle.33percent",
                    label: "CKP",
                    active: showCockpitPanel,
                    help: "Toggle cockpit mode panel",
                    action: onToggleCockpit
                )
                .keyboardShortcut("c", modifiers: [.command, .shift])

                TitleBarButton(
                    systemImage: pendingProposalCount > 0 ? "eye.badge.clock.fill" : "eye",
                    label: pendingProposalCount > 0 ? "RVW \(pendingProposalCount)" : "RVW",
                    active: pendingProposalCount > 0,
                    help: "Toggle review ribbon",
                    action: onToggleReview
                )
                .keyboardShortcut("r", modifiers: [.command, .shift])

                TitleBarButton(
                    systemImage: "play.circle",
                    label: "RUN",
                    active: false,
                    help: "Start a new development session",
                    action: onStartSession
                )

                TitleBarButton(
                    systemImage: "sidebar.trailing",
                    label: "INSP",
                    active: showInspector,
                    help: "Toggle inspector panel",
                    action: { showInspector.toggle() }
                )

                titleBarSeparator

                TitleBarButton(
                    systemImage: "doc.text",
                    label: "PRD",
                    active: false,
                    help: "Load a PRD file",
                    action: onLoadPRD
                )

                TitleBarButton(
                    systemImage: "clock.arrow.circlepath",
                    label: "HIST",
                    active: false,
                    help: "View past orchestrations",
                    action: onShowHistory
                )

                TitleBarButton(
                    systemImage: "brain.head.profile",
                    label: "INTEL",
                    active: false,
                    help: "Learning analytics, trust, memory, conflicts",
                    action: onShowIntelligence
                )

                TitleBarButton(
                    systemImage: "puzzlepiece.extension",
                    label: "SKL",
                    active: false,
                    help: "Browse available skills",
                    action: onShowSkills
                )

                TitleBarButton(
                    systemImage: "paintpalette",
                    label: "ART",
                    active: false,
                    help: "Open art direction pipeline",
                    action: onShowArtDirection
                )

                SettingsLink {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.Color.faint)
                        Text("SET")
                            .font(Theme.TextStyle.tacticalMono)
                            .tracking(Theme.Tracking.tacticalCaps)
                            .foregroundStyle(Theme.Color.faint)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open settings")
                .padding(.trailing, 12)
            }
        }
        .frame(height: 30)
        .background(Theme.Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Color.rule)
                .frame(height: Theme.Layout.ruleWidth)
        }
    }

    private var titleBarSeparator: some View {
        Rectangle()
            .fill(Theme.Color.rule)
            .frame(width: Theme.Layout.ruleWidth, height: 14)
            .padding(.horizontal, 6)
    }
}

// MARK: - TitleBarSuiteSwitcher

/// Tactical suite selector. Renders as `<suite> ↓` in mono caps, faint at rest,
/// ink on hover. No system menu chrome, no suite-color fill.
private struct TitleBarSuiteSwitcher: View {
    @Environment(\.appState) private var appState
    @State private var hovering = false
    @State private var isPresentingPopover = false

    private var activeSuite: Suite {
        Suite.builtIn.first(where: { $0.id == appState.activeSuiteId }) ?? .developer
    }

    var body: some View {
        Button {
            isPresentingPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(activeSuite.name.lowercased())
                    .font(Theme.TextStyle.tacticalMono)
                    .tracking(Theme.Tracking.tacticalCaps)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .regular))
            }
            .foregroundStyle(hovering ? Theme.Color.ink : Theme.Color.faint)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.tacticalHover, value: hovering)
        .popover(isPresented: $isPresentingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Suite.builtIn, id: \.id) { suite in
                    Button {
                        withAnimation(.linear(duration: Theme.Animation.normal)) {
                            appState.activeSuiteId = suite.id
                        }
                        NotificationCenter.default.post(
                            name: .suiteSwitched,
                            object: nil,
                            userInfo: ["suiteId": suite.id]
                        )
                        isPresentingPopover = false
                    } label: {
                        HStack {
                            Text(suite.name.lowercased())
                                .font(Theme.TextStyle.labelMono)
                            Spacer()
                            if suite.id == appState.activeSuiteId {
                                StatusPip(state: .active, animated: false)
                            }
                        }
                        .foregroundStyle(suite.id == appState.activeSuiteId ? Theme.Color.ink : Theme.Color.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 180)
            .background(Theme.Color.surface)
            .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: Theme.Layout.ruleWidth))
        }
    }
}

// MARK: - TitleBarButton

struct TitleBarButton: View {
    let systemImage: String
    let label: String
    let active: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .regular))
                Text(label)
                    .font(Theme.TextStyle.tacticalMono)
                    .tracking(Theme.Tracking.tacticalCaps)
            }
            .foregroundStyle(currentColor)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Motion.tacticalHover, value: hovering)
        .animation(Motion.tacticalHover, value: active)
    }

    private var currentColor: SwiftUI.Color {
        if active { return Theme.Color.voltage }
        if hovering { return Theme.Color.ink }
        return Theme.Color.faint
    }
}

#if DEBUG
struct TitleBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            TitleBar(
                showChatPanel: .constant(true),
                showInspector: .constant(true),
                showCockpitPanel: false,
                pendingProposalCount: 3,
                onToggleChat: {},
                onToggleCockpit: {},
                onToggleReview: {},
                onStartSession: {},
                onLoadPRD: {},
                onShowHistory: {},
                onShowIntelligence: {},
                onShowSkills: {},
                onShowArtDirection: {}
            )
            Theme.Color.void
                .frame(maxHeight: .infinity)
        }
        .frame(width: 1280, height: 200)
    }
}
#endif
