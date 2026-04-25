import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

// MARK: - PRDLoaderSheet (PRD Visualizer)

/// Full PRD visualizer with a sidebar listing all scanned PRDs in the repo
/// and a detail panel showing the selected PRD's content.
struct PRDLoaderSheet: View {
    private let initialURL: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState
    @StateObject private var viewModel = PRDLoaderViewModel()
    @State private var repoPath: String = ""
    @State private var isStarting: Bool = false
    @State private var showSlotAssignment: Bool = false
    @State private var selectedScannedPRD: ScannedPRD?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    private var repoURL: URL? {
        guard !repoPath.isEmpty else { return nil }
        return URL(fileURLWithPath: repoPath)
    }

    private var canStart: Bool {
        viewModel.document != nil && repoURL != nil && !isStarting
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content: sidebar + detail
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 240)

                Divider()

                detailPanel
            }

            Divider()

            // Footer actions
            actions
        }
        .frame(width: 860, height: 580)
        .background(Color.bgApp)
        .onAppear {
            loadInitialPRDIfNeeded()
            prefillRepoPath()
            // Trigger PRD scan if not done yet
            if appState.scannedPRDs.isEmpty {
                Task { await appState.scanPRDs() }
            }
        }
        .onDisappear {
            appState.setActivePRD(url: nil, name: nil)
        }
        .onChange(of: viewModel.document?.featureName ?? "") { _, _ in
            appState.setActivePRD(url: viewModel.selectedURL, name: viewModel.document?.featureName)
        }
        .sheet(isPresented: $showSlotAssignment) {
            if let doc = viewModel.document, let url = repoURL {
                SlotAssignmentSheet(prd: doc, repoPath: url) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentPrimary)

            Text("PRD Visualizer")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Spacer()

            // Scan status
            if appState.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning...")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Text("\(appState.scannedPRDs.count) PRD(s)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Button {
                Task { await appState.scanPRDs() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .help("Rescan project for PRDs")

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(Theme.Spacing.md)
        .background(Color.bgSurface)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section: Scanned PRDs
            HStack {
                Text("PROJECT PRDs")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)

            Divider()

            if appState.scannedPRDs.isEmpty && !appState.isScanning {
                VStack(spacing: Theme.Spacing.sm) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.textTertiary)
                    Text("No prd.json found")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Text("Use \"Load PRD...\" to import one")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.scannedPRDs) { prd in
                            PRDListRow(
                                prd: prd,
                                isSelected: selectedScannedPRD?.id == prd.id
                            ) {
                                selectScannedPRD(prd)
                            }
                        }
                    }
                }
            }

            Divider()

            // Manual load button
            Button {
                browseForPRD()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                    Text("Load PRD...")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentPrimary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .background(Color.bgCanvas)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repo path bar
            HStack(spacing: Theme.Spacing.sm) {
                Text("Repository")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                TextField("Select repository...", text: $repoPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("Browse") { browseForRepo() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(Theme.Spacing.sm)
            .background(Color.bgSurface)

            Divider()

            // PRD content
            if let doc = viewModel.document {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Title + metadata
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(doc.featureName)
                                .font(.title2.bold())
                                .foregroundStyle(Color.textPrimary)

                            Text(doc.description)
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)

                            HStack(spacing: Theme.Spacing.md) {
                                Label("\(doc.userStories.count) stories", systemImage: "list.bullet")
                                let criticalCount = doc.userStories.filter { $0.priority == .critical }.count
                                if criticalCount > 0 {
                                    Label("\(criticalCount) critical", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.statusWarning)
                                }
                                let completedCount = doc.userStories.filter { $0.status == .complete }.count
                                if completedCount > 0 {
                                    Label("\(completedCount) done", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(Color.statusSuccess)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)

                            // Progress bar
                            if !doc.userStories.isEmpty {
                                let completed = doc.userStories.filter { $0.status == .complete }.count
                                let progress = Double(completed) / Double(doc.userStories.count)
                                ProgressView(value: progress)
                                    .tint(progress >= 1.0 ? Color.statusSuccess : Color.accentPrimary)
                            }
                        }

                        Divider()

                        // Stories list
                        ForEach(doc.userStories) { story in
                            storyRow(story)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            } else if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.statusError)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.statusError)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.textTertiary)
                    Text("Select a PRD from the sidebar")
                        .font(.body)
                        .foregroundStyle(Color.textTertiary)
                    Text("or load one manually")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func storyRow(_ story: PRDUserStory) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                // Status icon
                Image(systemName: story.status == .complete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(story.status == .complete ? Color.statusSuccess : Color.textTertiary)

                Text("\(story.id) — \(story.title)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .strikethrough(story.status == .complete, color: Color.textTertiary)

                Spacer()

                // Priority badge
                Text(story.priority.rawValue.capitalized)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(story.priority).opacity(0.2))
                    .foregroundStyle(priorityColor(story.priority))
                    .clipShape(Capsule())
            }

            Text(story.description)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)

            if !story.dependsOn.isEmpty {
                Label("Depends on: \(story.dependsOn.joined(separator: ", "))", systemImage: "link")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func priorityColor(_ priority: PRDPriority) -> Color {
        switch priority {
        case .critical: return Color.statusError
        case .high: return Color.statusWarning
        case .medium: return Color.accentPrimary
        case .low: return Color.textTertiary
        }
    }

    // MARK: - Footer Actions

    private var actions: some View {
        HStack {
            if let selected = selectedScannedPRD {
                Text(selected.relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)

            Button {
                startOrchestration()
            } label: {
                if isStarting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 120)
                } else {
                    Text("Start Orchestration")
                        .frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.statusSuccess)
            .disabled(!canStart)
        }
        .padding(Theme.Spacing.md)
        .background(Color.bgSurface)
    }

    // MARK: - Actions

    private func selectScannedPRD(_ prd: ScannedPRD) {
        selectedScannedPRD = prd
        Task {
            await viewModel.load(url: prd.fileURL)
            // Auto-set repo path to parent of the prd.json if not already set
            if repoPath.isEmpty {
                repoPath = prd.fileURL.deletingLastPathComponent().path
            }
        }
    }

    private func startOrchestration() {
        guard viewModel.document != nil, repoURL != nil else { return }
        showSlotAssignment = true
    }

    private func prefillRepoPath() {
        if let path = appState.projectPath, !path.isEmpty {
            repoPath = path
        }
    }

    private func browseForRepo() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select git repository"
        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
        }
#endif
    }

    private func browseForPRD() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        panel.message = "Select prd.json"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.load(url: url)
                selectedScannedPRD = nil // manual load, not from scan
            }
        }
#endif
    }

    private func loadInitialPRDIfNeeded() {
        guard let url = initialURL,
              viewModel.document == nil else { return }
        Task {
            await viewModel.load(url: url)
        }
    }
}

// MARK: - PRD List Row

private struct PRDListRow: View {
    let prd: ScannedPRD
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                // Status indicator
                Circle()
                    .fill(prd.progress >= 1.0 ? Color.statusSuccess : Color.accentPrimary)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(prd.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(prd.relativePath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Story count
                Text("\(prd.completedStories)/\(prd.document.userStories.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isSelected ? Color.accentPrimary.opacity(0.15) : (isHovered ? Color.bgElevated : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
