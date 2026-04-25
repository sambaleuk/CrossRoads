import SwiftUI

// MARK: - RuntimesSettingsView

/// Phase 5: Agent runtime management — register custom agents, view built-ins, test health.
public struct RuntimesSettingsView: View {

    @State private var runtimes: [AgentRuntime] = []
    @State private var isLoading = false
    @State private var showAddSheet = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        Form {
            // Runtime list
            runtimeListSection

            // Actions
            actionsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.bgSurface)
        .padding()
        .sheet(isPresented: $showAddSheet) {
            AddRuntimeSheet(onSave: { runtime in
                runtimes.append(runtime)
                showAddSheet = false
            })
        }
    }

    // MARK: - Runtime List

    private var runtimeListSection: some View {
        Section {
            if runtimes.isEmpty && !isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.title2)
                            .foregroundStyle(Color.textTertiary)
                        Text("No runtimes registered")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                        Text("Click 'Register Built-ins' to add default agents")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            }

            ForEach(runtimes, id: \.id) { runtime in
                runtimeRow(runtime)
            }
        } header: {
            HStack {
                Label("Agent Runtimes", systemImage: "cpu")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            Text("Runtimes define how XRoads communicates with agent processes")
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func runtimeRow(_ runtime: AgentRuntime) -> some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(runtime.isEnabled ? Color.statusSuccess : Color.textTertiary)
                .frame(width: 8, height: 8)
                .shadow(color: runtime.isEnabled ? Color.statusSuccess.opacity(0.5) : .clear, radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(runtime.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)

                    Text(runtime.runtimeType)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.terminalMagenta)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.terminalMagenta.opacity(0.15))
                        .clipShape(Capsule())

                    if runtime.isBuiltin {
                        Text("built-in")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.bgElevated)
                            .clipShape(Capsule())
                    }
                }

                if let command = runtime.command, !command.isEmpty {
                    Text(command)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                // Register built-in runtimes
                let builtins = [
                    ("claude", "cli", "claude"),
                    ("gemini", "cli", "gemini"),
                    ("codex", "cli", "codex"),
                ]
                for (name, type, cmd) in builtins {
                    if !runtimes.contains(where: { $0.name == name }) {
                        let rt = AgentRuntime(
                            id: UUID(),
                            name: name,
                            runtimeType: type,
                            command: cmd,
                            url: nil,
                            dockerImage: nil,
                            healthCheckCommand: "\(cmd) --version",
                            configSchema: nil,
                            configDefaults: nil,
                            capabilities: "[\"code_edit\",\"test_run\",\"git_ops\",\"terminal\"]",
                            icon: nil,
                            color: nil,
                            isBuiltin: true,
                            isEnabled: true,
                            createdAt: Date()
                        )
                        runtimes.append(rt)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Register Built-in Runtimes (claude, gemini, codex)")
                }
            }
            .foregroundStyle(Color.accentPrimary)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.statusError)
            }
        }
    }
}

// MARK: - AddRuntimeSheet

struct AddRuntimeSheet: View {
    let onSave: (AgentRuntime) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var runtimeType = "cli"
    @State private var command = ""
    @State private var url = ""
    @State private var capabilities = "[\"code_edit\",\"test_run\"]"

    private let runtimeTypes = ["cli", "http", "docker", "script", "stdio"]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Agent Runtime")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $runtimeType) {
                    ForEach(runtimeTypes, id: \.self) { type in
                        Text(type.uppercased()).tag(type)
                    }
                }
                if runtimeType == "http" {
                    TextField("URL", text: $url)
                } else {
                    TextField("Command / Path", text: $command)
                }
                TextField("Capabilities (JSON)", text: $capabilities)
                    .font(.system(size: 11, design: .monospaced))
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Register") {
                    let runtime = AgentRuntime(
                        id: UUID(),
                        name: name,
                        runtimeType: runtimeType,
                        command: runtimeType != "http" ? command : nil,
                        url: runtimeType == "http" ? url : nil,
                        dockerImage: nil,
                        healthCheckCommand: nil,
                        configSchema: nil,
                        configDefaults: nil,
                        capabilities: capabilities,
                        icon: nil,
                        color: nil,
                        isBuiltin: false,
                        isEnabled: true,
                        createdAt: Date()
                    )
                    onSave(runtime)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 380)
        .background(Color.bgSurface)
    }
}
