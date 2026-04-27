import SwiftUI

/// Routing target for the orchestrator chat input.
/// `.api` wakes the cockpit brain (default); `.terminal` routes to the active
/// terminal slot via NotificationCenter.
enum OrchestratorChatMode: String, Hashable, CaseIterable {
    case api
    case terminal

    var label: String {
        switch self {
        case .api:      return "API"
        case .terminal: return "TERMINAL"
        }
    }
}

/// Idle-state orchestrator sidebar. Shown in the left column of MainWindowView
/// when no conversation is active. Renders the v2 spec section 8 pattern:
/// section header, brand mark, identity copy, TRY section with suggestion
/// pills, and a free-form input at the bottom.
struct OrchestratorSidebar: View {

    /// Test-only seed for the placeholder cursor visibility.
    var snapshotCursorOn: Bool? = nil

    @State private var inputText: String = ""
    @State private var cursorOn: Bool = true
    @State private var mode: OrchestratorChatMode = .api

    private let suggestions: [String] = [
        "scaffold a swift package",
        "review this branch",
        "spec a new feature"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            Spacer().frame(height: 24)

            identityBlock

            Spacer().frame(height: 32)

            tryBlock

            Spacer()

            inputBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.Color.void
                .africanPatternOverlay(.ndebele, opacity: 0.01)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.Color.rule)
                .frame(width: Theme.Layout.ruleWidth)
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Text("ORCHESTRATOR")
                .font(Theme.TextStyle.labelMono)
                .tracking(Theme.Tracking.labelMonoCaps)
                .foregroundStyle(Theme.Color.faint)

            Spacer()

            HStack(spacing: 6) {
                StatusPip(state: .connected)
                ChatModeToggle(mode: $mode)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    // MARK: - Identity

    private var identityBlock: some View {
        VStack(spacing: 10) {
            BrandMarkPlaceholder(size: 40)

            Text("xroads orchestrator")
                .font(Theme.Font.displayMedium(13))
                .foregroundStyle(Theme.Color.ink)

            Text("multi-agent orchestration")
                .font(Theme.Font.displayRegular(10))
                .tracking(Theme.Tracking.labelMonoCaps)
                .foregroundStyle(Theme.Color.faint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Try section

    private var tryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRY")
                .font(Theme.TextStyle.labelMono)
                .tracking(Theme.Tracking.labelMonoCaps)
                .foregroundStyle(Theme.Color.faint)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    SuggestionPill(text: suggestion) {
                        inputText = suggestion
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Input

    private var inputBlock: some View {
        OrchestratorInput(
            text: $inputText,
            placeholder: mode == .api ? "what are we building today?" : "type a terminal command…",
            cursorOverride: snapshotCursorOn,
            onSubmit: { performSubmit() }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func performSubmit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NotificationCenter.default.post(
            name: .orchestratorChatSubmit,
            object: nil,
            userInfo: ["text": trimmed, "mode": mode.rawValue]
        )
        inputText = ""
    }
}

// MARK: - ChatModeToggle

/// Compact 2-segment toggle in the sidebar header. Tap a segment to switch
/// the input routing target. Active segment uses voltage; inactive faint.
private struct ChatModeToggle: View {
    @Binding var mode: OrchestratorChatMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OrchestratorChatMode.allCases, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.label)
                        .font(Theme.Font.mono(9))
                        .tracking(Theme.Tracking.tacticalCaps)
                        .foregroundStyle(option == mode ? Theme.Color.voltage : Theme.Color.faint)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Route input to \(option.label.lowercased())")
                .accessibilityIdentifier("orchestrator.mode.\(option.rawValue)")
            }
        }
        .overlay(
            Rectangle()
                .stroke(Theme.Color.rule, lineWidth: Theme.Layout.ruleWidth)
        )
    }
}

// MARK: - SuggestionPill

private struct SuggestionPill: View {
    let text: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(Theme.TextStyle.labelMono)
                    .foregroundStyle(hovering ? Theme.Color.voltage : Theme.Color.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .overlay(
                Rectangle()
                    .stroke(
                        hovering ? Theme.Color.voltage : Theme.Color.faint,
                        lineWidth: Theme.Layout.ruleWidth
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.tacticalHover, value: hovering)
    }
}

// MARK: - OrchestratorInput

private struct OrchestratorInput: View {
    @Binding var text: String
    let placeholder: String

    /// Test-only override. When non-nil, freezes cursor visibility.
    var cursorOverride: Bool? = nil

    /// Submit handler — called on Enter, cmd+Enter, or send-button tap.
    /// Caller is expected to clear `text` after handling.
    var onSubmit: () -> Void = {}

    @State private var cursorOn: Bool = true
    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INPUT")
                .font(Theme.Font.mono(9))
                .tracking(Theme.Tracking.tacticalCaps)
                .foregroundStyle(Theme.Color.faint)

            HStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        HStack(spacing: 1) {
                            Text(placeholder)
                                .font(Theme.TextStyle.body)
                                .foregroundStyle(Theme.Color.faint)

                            Rectangle()
                                .fill(Theme.Color.voltage)
                                .frame(width: 2, height: 14)
                                .opacity((cursorOverride ?? cursorOn) ? 1 : 0)
                                .padding(.leading, 2)
                        }
                    }

                    // ImageRenderer cannot suppress macOS TextField default chrome,
                    // so the snapshot path skips the real field. The running app
                    // (cursorOverride == nil) gets the actual TextField.
                    if cursorOverride == nil {
                        TextField("", text: $text)
                            .textFieldStyle(.plain)
                            .font(Theme.TextStyle.body)
                            .foregroundStyle(Theme.Color.ink)
                            .focused($focused)
                            .onSubmit { onSubmit() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SendButton(active: canSubmit, action: onSubmit)
            }
            .frame(height: 32)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? Theme.Color.voltage : Theme.Color.rule)
                    .frame(height: Theme.Layout.ruleWidth)
            }
        }
        .onAppear {
            guard cursorOverride == nil else { return }
            withAnimation(Motion.cursorBlink) {
                cursorOn = false
            }
        }
    }
}

// MARK: - SendButton

/// Square send button anchored right of the input. Disabled (faint) when input
/// is empty or whitespace-only; voltage when ready. Bound to cmd+Return for
/// keyboard parity with the multi-line submit pattern used elsewhere.
private struct SendButton: View {
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Theme.Color.void : Theme.Color.faint)
                .frame(width: 24, height: 24)
                .background(
                    Rectangle()
                        .fill(active ? Theme.Color.voltage : Theme.Color.surface)
                )
                .overlay(
                    Rectangle()
                        .stroke(active ? Theme.Color.voltage : Theme.Color.rule,
                                lineWidth: Theme.Layout.ruleWidth)
                )
                .opacity(active ? (hovering ? 0.85 : 1.0) : 0.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .keyboardShortcut(.return, modifiers: .command)
        .onHover { hovering = $0 }
        .animation(Motion.tacticalHover, value: hovering)
        .help("Send (Enter or ⌘↩)")
        .accessibilityIdentifier("orchestrator.send")
    }
}

#if DEBUG
struct OrchestratorSidebar_Previews: PreviewProvider {
    static var previews: some View {
        OrchestratorSidebar(snapshotCursorOn: true)
            .frame(width: 320, height: 720)
    }
}
#endif
