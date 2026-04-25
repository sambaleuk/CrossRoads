import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - WorkspaceSwitcherView

/// Narrow sidebar component for switching between workspaces.
/// Shows color-coded badges with first letter + name. 44pt width.
struct WorkspaceSwitcherView: View {

    @State private var workspaces: [Workspace] = []
    @State private var activeWorkspaceId: UUID?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var renamingWorkspace: Workspace?
    @State private var renameText: String = ""
    @State private var showRenameAlert: Bool = false

    let workspaceRepository: WorkspaceRepository?

    init(workspaceRepository: WorkspaceRepository? = nil) {
        self.workspaceRepository = workspaceRepository
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspaces list
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(workspaces) { workspace in
                        WorkspaceBadge(
                            workspace: workspace,
                            isActive: workspace.id == activeWorkspaceId
                        )
                        .onTapGesture {
                            switchWorkspace(workspace)
                        }
                        .contextMenu {
                            Button {
                                renamingWorkspace = workspace
                                renameText = workspace.name
                                showRenameAlert = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                deleteWorkspace(workspace)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, 4)
            }

            Spacer()

            Divider()
                .background(Color.borderMuted)

            // Add workspace button
            Button {
                addWorkspace()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .buttonStyle(.plain)
            .help("Add Workspace")
            .padding(.vertical, Theme.Spacing.sm)
        }
        .frame(width: 44)
        .background(Color.bgSurface)
        .task {
            await loadWorkspaces()
        }
        .alert("Rename Workspace", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let ws = renamingWorkspace {
                    renameWorkspace(ws, newName: renameText)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadWorkspaces() async {
        guard let repo = workspaceRepository else { return }
        do {
            workspaces = try await repo.fetchAll()
            activeWorkspaceId = workspaces.first(where: { $0.isActive })?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func switchWorkspace(_ workspace: Workspace) {
        guard let repo = workspaceRepository else { return }
        Task {
            do {
                try await repo.switchActive(id: workspace.id)
                await loadWorkspaces()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addWorkspace() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder for the new workspace"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.lastPathComponent
        let ws = Workspace(
            name: name,
            projectPath: url.path,
            color: randomColor(),
            isActive: false
        )

        guard let repo = workspaceRepository else { return }
        Task {
            do {
                _ = try await repo.createWorkspace(ws)
                await loadWorkspaces()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    private func deleteWorkspace(_ workspace: Workspace) {
        guard let repo = workspaceRepository else { return }
        Task {
            do {
                try await repo.deleteWorkspace(id: workspace.id)
                await loadWorkspaces()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renameWorkspace(_ workspace: Workspace, newName: String) {
        guard let repo = workspaceRepository else { return }
        var updated = workspace
        updated.name = newName
        Task {
            do {
                _ = try await repo.updateWorkspace(updated)
                await loadWorkspaces()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func randomColor() -> String {
        let colors = ["#0DF170", "#FF6B6B", "#4ECDC4", "#45B7D1", "#F7DC6F", "#BB8FCE", "#E59866"]
        return colors.randomElement() ?? "#0DF170"
    }
}

// MARK: - WorkspaceBadge

private struct WorkspaceBadge: View {
    let workspace: Workspace
    let isActive: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Color(hex: workspace.color).opacity(0.2))
                    .frame(width: 32, height: 32)

                Text(String(workspace.name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: workspace.color))
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(isActive ? Color.accentPrimary : Color.clear, lineWidth: 2)
            )

            // Color dot indicator
            Circle()
                .fill(Color(hex: workspace.color))
                .frame(width: 4, height: 4)
                .opacity(isActive ? 1.0 : 0.0)
        }
        .help(workspace.name)
    }
}

// MARK: - Preview

#if DEBUG
struct WorkspaceSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        WorkspaceSwitcherView()
            .frame(height: 400)
            .background(Color.bgApp)
    }
}
#endif
