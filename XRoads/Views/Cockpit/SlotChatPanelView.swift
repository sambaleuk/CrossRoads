import SwiftUI

// MARK: - SlotChatPanelView

/// Expandable chat panel for a single agent slot. Displays AgentMessage history
/// and provides a text input for injecting messages into agent stdin.
///
/// US-004: Cockpit UI — chat panel per slot + Chairman feed display
struct SlotChatPanelView: View {
    @Bindable var viewModel: SlotChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(viewModel.messages, id: \.id) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            Divider()

            // Input bar
            HStack(spacing: Theme.Spacing.xs) {
                TextField("Message agent...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        Task { await viewModel.sendMessage() }
                    }

                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.textTertiary
                                : Color.accentPrimary
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)
        }
        .background(Color.bgCanvas)
        .task {
            await viewModel.loadMessages()
            await viewModel.startListening()
            viewModel.markAllAsRead()
        }
    }
}

// MARK: - MessageBubbleView

/// Renders a single AgentMessage in the chat panel.
private struct MessageBubbleView: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Type badge + timestamp
            HStack(spacing: 4) {
                Text(message.messageType.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(typeColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(typeColor.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                Text(message.createdAt, style: .time)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }

            // Content
            Text(message.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.xs)
        .background(Color.bgSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
    }

    private var typeColor: Color {
        switch message.messageType {
        case .status: return Color.statusInfo
        case .question: return Color.accentPrimary
        case .blocker: return Color.statusError
        case .completion: return Color.statusSuccess
        case .chairmanBrief: return Color.terminalCyan
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SlotChatPanelView_Previews: PreviewProvider {
    static var previews: some View {
        Text("SlotChatPanelView requires DI setup for preview")
            .foregroundStyle(Color.textTertiary)
            .frame(width: 300, height: 200)
            .background(Color.bgApp)
    }
}
#endif
