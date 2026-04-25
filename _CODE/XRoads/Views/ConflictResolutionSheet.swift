import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ConflictResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    @State private var errorMessage: String?
    @State private var isCommitting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Resolve Conflicts")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Close") {
                    appState.dismissConflictSheet()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(Theme.Spacing.md)

            Divider()

            // Content
            HStack(spacing: Theme.Spacing.lg) {
                conflictList
                    .frame(width: 220)
                conflictDetail
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 800, height: 520)
        .background(Color.bgApp)
    }

    private var conflictList: some View {
        List(selection: selectedFileBinding) {
            if appState.conflictFiles.isEmpty {
                Text("No conflicts — ready to merge")
                    .foregroundStyle(Color.statusSuccess)
            } else {
                ForEach(appState.conflictFiles, id: \.self) { file in
                    Label(file, systemImage: "doc.richtext")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .listStyle(.inset)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var conflictDetail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if appState.conflictFiles.isEmpty {
                // All conflicts resolved — show commit action
                allResolvedView
            } else {
                // Active conflict resolution
                Text(selectedFileBinding.wrappedValue ?? "Select a file")
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)

                Text("Choose how to resolve this conflict. You can pick the orchestrator's version (ours), the agent's version (theirs), or open the file in your editor for manual edits.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                HStack {
                    Button("Keep Ours") {
                        resolveCurrent(keepOurs: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFileBinding.wrappedValue == nil)

                    Button("Keep Theirs") {
                        resolveCurrent(keepOurs: false)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedFileBinding.wrappedValue == nil)

                    Button("Mark as Resolved") {
                        markCurrentResolved()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedFileBinding.wrappedValue == nil)

                    Spacer()

                    Button {
                        openInEditor()
                    } label: {
                        Label("Open in Editor", systemImage: "arrow.up.forward.app")
                    }
                    .disabled(selectedFileBinding.wrappedValue == nil)
                }
            }

            // Error feedback
            if let error = errorMessage {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusError)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.statusError)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.sm)
                .background(Color.statusError.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            Spacer()

            // Bottom actions
            HStack {
                Button(role: .destructive) {
                    Task {
                        await appState.abortMerge()
                        dismiss()
                    }
                } label: {
                    Label("Abort Merge", systemImage: "xmark.octagon")
                }

                Spacer()

                if appState.conflictFiles.isEmpty {
                    Button {
                        commitMerge()
                    } label: {
                        Label("Complete Merge", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.statusSuccess)
                    .disabled(isCommitting)
                }
            }
        }
    }

    private var allResolvedView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(Color.statusSuccess)
            Text("All conflicts resolved")
                .font(.title3.bold())
                .foregroundStyle(Color.textPrimary)
            Text("Click \"Complete Merge\" to commit the resolved merge.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    private var selectedFileBinding: Binding<String?> {
        Binding(
            get: {
                appState.selectedConflictFile ?? appState.conflictFiles.first
            },
            set: { newValue in
                appState.selectedConflictFile = newValue
            }
        )
    }

    private func resolveCurrent(keepOurs: Bool) {
        guard let file = selectedFileBinding.wrappedValue else { return }
        errorMessage = nil
        Task {
            if keepOurs {
                await appState.keepOurs(for: file)
            } else {
                await appState.keepTheirs(for: file)
            }
            // Check if an error was set
            if let appError = appState.error {
                errorMessage = appError.localizedDescription
                appState.clearError()
            }
        }
    }

    private func markCurrentResolved() {
        guard let file = selectedFileBinding.wrappedValue else { return }
        errorMessage = nil
        Task {
            await appState.markResolved(file: file)
            if let appError = appState.error {
                errorMessage = appError.localizedDescription
                appState.clearError()
            }
        }
    }

    private func commitMerge() {
        errorMessage = nil
        isCommitting = true
        Task {
            await appState.commitResolvedMerge()
            isCommitting = false
            if let appError = appState.error {
                errorMessage = appError.localizedDescription
                appState.clearError()
            } else {
                dismiss()
            }
        }
    }

    private func openInEditor() {
#if os(macOS)
        guard let repo = appState.orchestrationRepoPath,
              let file = selectedFileBinding.wrappedValue else { return }
        let url = repo.appendingPathComponent(file)
        NSWorkspace.shared.open(url)
#endif
    }
}
