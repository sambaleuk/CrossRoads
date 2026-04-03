import SwiftUI
import WebKit

// MARK: - ReviewRibbonView

/// Full-screen overlay that serves as both a code review panel and a brain
/// proposal approval gate. Slides down from the top of the app window.
///
/// Two modes:
/// - **Review mode**: Browse repo files, view diffs, rendered markdown, syntax-highlighted code.
/// - **Approval mode**: Brain proposals (launches, suite switches, decisions) with approve/reject/modify.
struct ReviewRibbonView: View {
    @Bindable var viewModel: CockpitViewModel
    @Environment(\.appState) private var appState
    let projectPath: String

    @State private var selectedTab: RibbonTab = .proposals
    @State private var rootNode: TreeNode?
    @State private var selectedFile: TreeNode?
    @State private var selectedScannedPRD: ScannedPRD?
    @State private var selectedStory: PRDUserStory?
    @State private var fileContent: String = ""
    @State private var oldFileContent: String = ""  // git HEAD version for split diff
    @State private var isLoadingFile: Bool = false
    @State private var searchText: String = ""
    @State private var modifiedFiles: Set<String> = []  // relative paths from git status
    @State private var gitBranch: String = ""
    @State private var gitLastCommit: String = ""

    enum RibbonTab: String, CaseIterable {
        case proposals = "Proposals"
        case files = "Files"
        case prd = "PRD"
        case preview = "Preview"
    }

    var body: some View {
        VStack(spacing: 0) {
            ribbonHeader

            Divider()
                .background(Color.borderMuted)

            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 280)

                Divider()
                    .background(Color.borderMuted)

                mainContent
            }
        }
        .background(Color.bgCanvas.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Color.borderMuted, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .padding(Theme.Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            loadFileTree()
            loadGitInfo()
            loadPRD()
            if !viewModel.pendingProposals.isEmpty {
                selectedTab = .proposals
            }
        }
        .onChange(of: appState.scannedPRDs.count) { _, newCount in
            if newCount > 0 && selectedScannedPRD == nil {
                selectedScannedPRD = appState.scannedPRDs.first
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var ribbonHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(RibbonTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tabIcon(tab))
                                .font(.system(size: 10))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: selectedTab == tab ? .bold : .medium, design: .monospaced))
                            if tab == .proposals && !viewModel.pendingProposals.isEmpty {
                                Text("\(viewModel.pendingProposals.count)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.statusError)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? Color.textPrimary : Color.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.bgElevated : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)

            Spacer()

            if !viewModel.pendingProposals.isEmpty {
                Button {
                    Task { await viewModel.approveAllProposals() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Approve All (\(viewModel.pendingProposals.count))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.statusSuccess)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.Spacing.sm)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showReviewRibbon = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color.bgApp)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarView: some View {
        switch selectedTab {
        case .proposals:
            proposalsSidebar
        case .files:
            fileTreeSidebar
        case .prd:
            prdStorySidebar
        case .preview:
            fileTreeSidebar
        }
    }

    @ViewBuilder
    private var proposalsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PENDING ACTIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)

            if viewModel.pendingProposals.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.statusSuccess.opacity(0.5))
                    Text("No pending proposals")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xs) {
                        ForEach(Array(viewModel.pendingProposals.values).sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { proposal in
                            ProposalSidebarItem(proposal: proposal)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .background(Color.bgApp)
    }

    @ViewBuilder
    private var fileTreeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                TextField("Filter files...", text: $searchText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .padding(Theme.Spacing.sm)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let root = rootNode {
                        ForEach(root.children, id: \.id) { child in
                            TreeNodeRow(
                                node: child,
                                selectedPath: selectedFile?.fullPath,
                                filter: searchText,
                                modifiedFiles: modifiedFiles,
                                depth: 0,
                                onSelect: { node in
                                    if !node.isDirectory {
                                        selectedFile = node
                                        loadFileContent(node)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .background(Color.bgApp)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .proposals:
            proposalsMainContent
        case .files:
            fileViewerContent
        case .prd:
            prdVisualizerContent
        case .preview:
            webPreviewContent
        }
    }

    @ViewBuilder
    private var proposalsMainContent: some View {
        if viewModel.pendingProposals.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.textTertiary.opacity(0.4))
                Text("Brain is thinking...")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                Text("Proposals will appear here when the brain recommends actions.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textTertiary.opacity(0.7))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(viewModel.pendingProposals.values).sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { proposal in
                        ProposalDetailCard(
                            proposal: proposal,
                            onApprove: { Task { await viewModel.approveProposal(proposal) } },
                            onReject: { viewModel.rejectProposal(proposal) }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private var fileViewerContent: some View {
        if isLoadingFile {
            VStack {
                Spacer()
                ProgressView("Loading...")
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let file = selectedFile {
            let isModified = modifiedFiles.contains(file.relativePath)

            VStack(alignment: .leading, spacing: 0) {
                // Git info bar: branch + last commit + file path
                HStack(spacing: 6) {
                    if !gitBranch.isEmpty {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.statusSuccess)
                        Text(gitBranch)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.statusSuccess)
                    }
                    if !gitLastCommit.isEmpty {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textTertiary)
                        Text(gitLastCommit)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 4)
                .background(Color.bgApp.opacity(0.6))

                // File path header
                HStack {
                    Image(systemName: fileIconForExt((file.name as NSString).pathExtension))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.terminalCyan)
                    Text(file.relativePath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                    if isModified {
                        Text("MODIFIED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.statusWarning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.statusWarning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    let lineCount = fileContent.components(separatedBy: "\n").count
                    Text("\(lineCount) lines")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.bgApp)

                Divider().background(Color.borderMuted)

                // Content: split diff or normal view
                if isModified && !oldFileContent.isEmpty {
                    SplitDiffView(
                        oldContent: oldFileContent,
                        newContent: fileContent,
                        fileName: file.name
                    )
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        RenderedContentView(
                            content: fileContent,
                            fileName: file.name
                        )
                        .padding(Theme.Spacing.md)
                    }
                }
            }
        } else {
            VStack {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.textTertiary.opacity(0.3))
                Text("Select a file to view")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Web Preview

    @ViewBuilder
    private var webPreviewContent: some View {
        VStack(spacing: 0) {
            // URL bar
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)

                TextField("URL", text: $viewModel.previewURL, onCommit: {})
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Color.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                Button {
                    // Force reload by toggling URL
                    let current = viewModel.previewURL
                    viewModel.previewURL = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        viewModel.previewURL = current
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Color.bgApp)

            Divider().background(Color.borderMuted)

            // WebView + Agent Vision overlay
            if let url = URL(string: viewModel.previewURL), !viewModel.previewURL.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    WebPreviewView(url: url)

                    // Agent Vision PIP — latest screenshot from Playwright
                    if let screenshotData = viewModel.agentScreenshots.values.first,
                       let nsImage = NSImage(data: screenshotData) {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.statusSuccess)
                                    .frame(width: 6, height: 6)
                                Text("AGENT VISION")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.statusSuccess)
                            }
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 320, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .stroke(Color.statusSuccess.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Color.bgCanvas.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .shadow(color: .black.opacity(0.3), radius: 8)
                        .padding(Theme.Spacing.md)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "globe")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.textTertiary.opacity(0.3))
                    Text("Enter a URL to preview")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                    Text("e.g. http://localhost:3000")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func tabIcon(_ tab: RibbonTab) -> String {
        switch tab {
        case .proposals: return "brain.head.profile"
        case .files: return "folder"
        case .prd: return "list.clipboard"
        case .preview: return "globe"
        }
    }

    private func fileIconForExt(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "yml", "yaml": return "list.bullet.indent"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "rs": return "gearshape"
        case "html", "css": return "globe"
        default: return "doc.text"
        }
    }

    // MARK: - Data Loading

    private func loadFileTree() {
        let path = projectPath
        Task.detached {
            // Run `find` on background thread to avoid blocking the main thread
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            process.arguments = [
                path, "-maxdepth", "4",
                "-not", "-path", "*/.*",
                "-not", "-path", "*/node_modules/*",
                "-not", "-path", "*/.build/*",
                "-not", "-path", "*/target/*",
                "-not", "-path", "*/__pycache__/*",
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do { try process.run() } catch { return }
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let paths = output.components(separatedBy: "\n")
                .filter { !$0.isEmpty && $0 != path }
                .sorted()

            // Collect file metadata on background thread (no TreeNode yet)
            struct FileEntry { let fullPath: String; let relativePath: String; let isDirectory: Bool }
            var entries: [FileEntry] = []
            for filePath in paths.prefix(500) {
                let relativePath = String(filePath.dropFirst(path.count + 1))
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir)
                entries.append(FileEntry(fullPath: filePath, relativePath: relativePath, isDirectory: isDir.boolValue))
            }

            // Build TreeNode on MainActor (TreeNode is @MainActor-isolated)
            let snapshot = entries
            await MainActor.run {
                let root = TreeNode(name: URL(fileURLWithPath: path).lastPathComponent, isDirectory: true)
                root.fullPath = path
                root.relativePath = ""

                for entry in snapshot {
                    root.insertPath(components: entry.relativePath.components(separatedBy: "/"),
                                    fullPath: entry.fullPath,
                                    relativePath: entry.relativePath,
                                    isDirectory: entry.isDirectory)
                }

                root.compact()
                root.sortRecursive()
                root.expandToDepth(2)
                self.rootNode = root
            }
        }
    }

    private func loadFileContent(_ node: TreeNode) {
        guard !node.isDirectory else { return }
        isLoadingFile = true
        oldFileContent = ""
        Task {
            do {
                let content = try String(contentsOfFile: node.fullPath, encoding: .utf8)

                // If file is modified, also load the HEAD version for split diff
                var oldContent = ""
                if modifiedFiles.contains(node.relativePath) {
                    oldContent = runGit(["-C", projectPath, "show", "HEAD:\(node.relativePath)"]) ?? ""
                }

                await MainActor.run {
                    fileContent = content
                    oldFileContent = oldContent
                    isLoadingFile = false
                }
            } catch {
                await MainActor.run {
                    fileContent = "Error reading file: \(error.localizedDescription)"
                    isLoadingFile = false
                }
            }
        }
    }

    private func loadGitInfo() {
        let path = projectPath
        Task.detached {
            let branch = Self.runGitDetached(["-C", path, "branch", "--show-current"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lastCommit = Self.runGitDetached(["-C", path, "log", "--oneline", "-1"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let statusOutput = Self.runGitDetached(["-C", path, "status", "--porcelain"]) ?? ""

            let modified = Set(
                statusOutput.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .compactMap { line -> String? in
                        // Format: " M path" or "M  path" or "?? path" etc.
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.count > 2 else { return nil }
                        let pathPart = String(line.dropFirst(3))
                        return pathPart.trimmingCharacters(in: .whitespaces)
                    }
            )

            await MainActor.run {
                self.gitBranch = branch
                self.gitLastCommit = lastCommit
                self.modifiedFiles = modified
            }
        }
    }

    /// Run a git command synchronously and return stdout.
    // MARK: - PRD Loading

    private func loadPRD() {
        // Ensure projectPath is set on appState (ReviewRibbon receives it directly)
        if (appState.projectPath ?? "").isEmpty && !projectPath.isEmpty {
            Task { @MainActor in
                appState.projectPath = projectPath
            }
        }
        // Trigger a scan — always, to get fresh results
        Task {
            // Use the local projectPath as fallback if appState.projectPath is nil
            let scanPath = appState.projectPath ?? projectPath
            guard !scanPath.isEmpty else { return }
            if appState.projectPath == nil {
                appState.projectPath = scanPath
            }
            await appState.scanPRDs()
            // Auto-select the first PRD
            if selectedScannedPRD == nil, let first = appState.scannedPRDs.first {
                selectedScannedPRD = first
            }
        }
    }

    // MARK: - PRD Sidebar

    @ViewBuilder
    private var prdStorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // PRD selector (when multiple PRDs exist)
            if appState.scannedPRDs.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRDs (\(appState.scannedPRDs.count))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(appState.scannedPRDs) { prd in
                                Button {
                                    selectedScannedPRD = prd
                                    selectedStory = nil
                                } label: {
                                    Text(prd.displayName)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(selectedScannedPRD?.id == prd.id ? Color.accentPrimary.opacity(0.2) : Color.bgElevated)
                                        .foregroundStyle(selectedScannedPRD?.id == prd.id ? Color.accentPrimary : Color.textSecondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                Divider().background(Color.borderMuted)
            } else if appState.scannedPRDs.count == 1 {
                // Single PRD header
                HStack {
                    Text(appState.scannedPRDs[0].displayName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(Theme.Spacing.sm)
                Divider().background(Color.borderMuted)
            }

            if let doc = selectedScannedPRD?.document ?? appState.scannedPRDs.first?.document {
                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PROGRESS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text("\(Int(doc.progress * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.statusSuccess)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.bgElevated)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.statusSuccess)
                                .frame(width: geo.size.width * doc.progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    let completed = doc.userStories.filter { $0.status == .complete }.count
                    Text("\(completed)/\(doc.userStories.count) stories")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Theme.Spacing.sm)

                Divider().background(Color.borderMuted)

                // Story list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(doc.userStories) { story in
                            Button {
                                selectedStory = story
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(storyStatusColor(story.status))
                                        .frame(width: 6, height: 6)
                                    Text(story.id)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.textTertiary)
                                    Text(story.title)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(selectedStory?.id == story.id ? Color.textPrimary : Color.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    priorityBadge(story.priority)
                                }
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(selectedStory?.id == story.id ? Color.bgElevated : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    Spacer()
                    if appState.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.textTertiary.opacity(0.4))
                        Text("No PRD found")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                        Button {
                            Task { await appState.scanPRDs() }
                        } label: {
                            Label("Scan project", systemImage: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.bgApp)
    }

    // MARK: - PRD Visualizer (Kanban + Detail)

    @ViewBuilder
    private var prdVisualizerContent: some View {
        if let doc = selectedScannedPRD?.document ?? appState.scannedPRDs.first?.document {
            VStack(spacing: 0) {
                // Header: feature name + description
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.featureName)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                        Text(doc.description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                    // Stats
                    HStack(spacing: Theme.Spacing.md) {
                        statBadge(label: "Total", value: "\(doc.userStories.count)", color: Color.textSecondary)
                        statBadge(label: "Done", value: "\(doc.userStories.filter { $0.status == .complete }.count)", color: Color.statusSuccess)
                        statBadge(label: "Active", value: "\(doc.userStories.filter { $0.status == .inProgress }.count)", color: Color.terminalCyan)
                        statBadge(label: "Blocked", value: "\(doc.userStories.filter { $0.status == .blocked }.count)", color: Color.statusError)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.bgApp)

                Divider().background(Color.borderMuted)

                if let story = selectedStory {
                    // Detail view for selected story
                    storyDetailView(story, doc: doc)
                } else {
                    // Kanban board
                    kanbanBoard(doc)
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Image(systemName: "list.clipboard")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.textTertiary.opacity(0.3))
                Text("No PRD loaded")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                Text("Open a project with a prd*.json file")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textTertiary.opacity(0.6))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func kanbanBoard(_ doc: PRDDocument) -> some View {
        let columns: [(title: String, status: PRDStoryStatus, color: Color)] = [
            ("PENDING", .pending, Color.textTertiary),
            ("IN PROGRESS", .inProgress, Color.terminalCyan),
            ("DONE", .complete, Color.statusSuccess),
            ("BLOCKED", .blocked, Color.statusError),
        ]

        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(columns, id: \.title) { col in
                    let stories = doc.userStories.filter { $0.status == col.status }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        // Column header
                        HStack {
                            Circle()
                                .fill(col.color)
                                .frame(width: 6, height: 6)
                            Text(col.title)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(col.color)
                            Spacer()
                            Text("\(stories.count)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)

                        Divider().background(col.color.opacity(0.3))

                        // Story cards
                        ScrollView {
                            LazyVStack(spacing: Theme.Spacing.xs) {
                                ForEach(stories) { story in
                                    Button {
                                        selectedStory = story
                                    } label: {
                                        kanbanCard(story, doc: doc)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.xs)
                        }
                    }
                    .frame(width: 240)
                    .background(Color.bgApp.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(col.color.opacity(0.15), lineWidth: 1)
                    )
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    @ViewBuilder
    private func kanbanCard(_ story: PRDUserStory, doc: PRDDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(story.id)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.terminalCyan)
                Spacer()
                priorityBadge(story.priority)
            }

            Text(story.title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            // Dependencies indicator
            if !story.dependsOn.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.textTertiary)
                    Text(story.dependsOn.joined(separator: ", "))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            // Test status
            if let test = story.unitTest {
                HStack(spacing: 3) {
                    Image(systemName: test.status == .passing ? "checkmark.circle.fill" : test.status == .failing ? "xmark.circle.fill" : "circle")
                        .font(.system(size: 8))
                        .foregroundStyle(test.status == .passing ? Color.statusSuccess : test.status == .failing ? Color.statusError : Color.textTertiary)
                    Text(test.status.rawValue)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.borderMuted, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func storyDetailView(_ story: PRDUserStory, doc: PRDDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Back button
                Button {
                    selectedStory = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                        Text("Back to board")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(Color.terminalCyan)
                }
                .buttonStyle(.plain)

                // Story header
                HStack {
                    Text(story.id)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.terminalCyan)
                    priorityBadge(story.priority)
                    Circle()
                        .fill(storyStatusColor(story.status))
                        .frame(width: 8, height: 8)
                    Text(story.status.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(storyStatusColor(story.status))
                    Spacer()
                    if story.estimatedComplexity > 0 {
                        Text("Complexity: \(story.estimatedComplexity)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Title
                Text(story.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                // Description
                Text(story.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)

                // Dependencies
                if !story.dependsOn.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEPENDENCIES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                        ForEach(story.dependsOn, id: \.self) { depId in
                            let dep = doc.userStories.first { $0.id == depId }
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.textTertiary)
                                Text(depId)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.terminalCyan)
                                if let dep {
                                    Text(dep.title)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Circle()
                                        .fill(storyStatusColor(dep.status))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Color.bgApp)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }

                // Acceptance criteria
                if !story.acceptanceCriteria.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ACCEPTANCE CRITERIA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                        ForEach(Array(story.acceptanceCriteria.enumerated()), id: \.offset) { _, criteria in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.square")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.statusSuccess.opacity(0.6))
                                Text(criteria)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Color.bgApp)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }

                // Unit test
                if let test = story.unitTest {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("UNIT TEST")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(test.status.rawValue.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(test.status == .passing ? Color.statusSuccess : test.status == .failing ? Color.statusError : Color.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background((test.status == .passing ? Color.statusSuccess : test.status == .failing ? Color.statusError : Color.textTertiary).opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if !test.file.isEmpty {
                            Text(test.file)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.terminalCyan)
                        }
                        Text(test.description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                        if !test.assertions.isEmpty {
                            ForEach(test.assertions, id: \.self) { assertion in
                                HStack(spacing: 4) {
                                    Text("•")
                                        .foregroundStyle(Color.terminalCyan)
                                    Text(assertion)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Color.bgApp)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    // MARK: - PRD Helpers

    private func storyStatusColor(_ status: PRDStoryStatus) -> Color {
        switch status {
        case .pending: return Color.textTertiary
        case .inProgress: return Color.terminalCyan
        case .complete: return Color.statusSuccess
        case .blocked: return Color.statusError
        }
    }

    @ViewBuilder
    private func priorityBadge(_ priority: PRDPriority) -> some View {
        let color: Color = {
            switch priority {
            case .critical: return Color.statusError
            case .high: return Color.statusWarning
            case .medium: return Color.terminalYellow
            case .low: return Color.textTertiary
            }
        }()
        Text(priority.displayName.prefix(1).uppercased())
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 14, height: 14)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func runGit(_ arguments: [String]) -> String? {
        Self.runGitDetached(arguments)
    }

    /// Static version callable from `Task.detached` (no actor isolation needed).
    private static func runGitDetached(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - TreeNode — Hierarchical file tree model

@MainActor
final class TreeNode: Identifiable, ObservableObject {
    let id = UUID()
    var name: String
    var isDirectory: Bool
    var fullPath: String = ""
    var relativePath: String = ""
    @Published var isExpanded: Bool = false
    var children: [TreeNode] = []

    init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }

    /// Insert a path (split into components) into the tree.
    func insertPath(components: [String], fullPath: String, relativePath: String, isDirectory: Bool) {
        guard let first = components.first else { return }

        if let existing = children.first(where: { $0.name == first }) {
            if components.count == 1 {
                // Leaf: update metadata
                existing.fullPath = fullPath
                existing.relativePath = relativePath
                existing.isDirectory = isDirectory
            } else {
                existing.insertPath(components: Array(components.dropFirst()),
                                    fullPath: fullPath,
                                    relativePath: relativePath,
                                    isDirectory: isDirectory)
            }
        } else {
            let node = TreeNode(name: first, isDirectory: components.count > 1 || isDirectory)
            if components.count == 1 {
                node.fullPath = fullPath
                node.relativePath = relativePath
                node.isDirectory = isDirectory
            } else {
                // Intermediate directory
                let parentRelPath = components[0..<1].joined(separator: "/")
                node.fullPath = fullPath.components(separatedBy: "/").dropLast(components.count - 1).joined(separator: "/")
                node.relativePath = parentRelPath
                node.isDirectory = true
            }
            children.append(node)
            if components.count > 1 {
                node.insertPath(components: Array(components.dropFirst()),
                                fullPath: fullPath,
                                relativePath: relativePath,
                                isDirectory: isDirectory)
            }
        }
    }

    /// Compact single-child directories: `src` > `services` → `src/services`
    func compact() {
        for child in children {
            child.compact()
        }
        // If this directory has exactly one child that's also a directory, merge them
        while children.count == 1, let only = children.first, only.isDirectory, !only.children.isEmpty {
            name = name + "/" + only.name
            fullPath = only.fullPath
            relativePath = only.relativePath
            children = only.children
        }
    }

    /// Sort recursively: directories first, then alphabetical.
    func sortRecursive() {
        children.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        for child in children {
            child.sortRecursive()
        }
    }

    /// Expand directories down to a given depth.
    func expandToDepth(_ depth: Int) {
        guard depth > 0, isDirectory else { return }
        isExpanded = true
        for child in children {
            child.expandToDepth(depth - 1)
        }
    }

    /// Flatten visible nodes (for search filtering).
    func matchesFilter(_ filter: String) -> Bool {
        if filter.isEmpty { return true }
        if name.localizedCaseInsensitiveContains(filter) { return true }
        return children.contains { $0.matchesFilter(filter) }
    }
}

// MARK: - TreeNodeRow — Recursive collapsible row

struct TreeNodeRow: View {
    @ObservedObject var node: TreeNode
    let selectedPath: String?
    let filter: String
    let modifiedFiles: Set<String>
    let depth: Int
    let onSelect: (TreeNode) -> Void

    private var isModified: Bool {
        !node.isDirectory && modifiedFiles.contains(node.relativePath)
    }

    var body: some View {
        if !node.matchesFilter(filter) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if node.isDirectory {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            node.isExpanded.toggle()
                        }
                    } else {
                        onSelect(node)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Spacer()
                            .frame(width: CGFloat(depth) * 14)

                        if node.isDirectory {
                            Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                                .frame(width: 10)
                        } else {
                            Spacer().frame(width: 10)
                        }

                        Image(systemName: nodeIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(nodeIconColor)

                        Text(node.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                            .lineLimit(1)

                        // Modified dot indicator
                        if isModified {
                            Circle()
                                .fill(Color.statusWarning)
                                .frame(width: 5, height: 5)
                        }

                        if node.isDirectory && !node.children.isEmpty {
                            Text("\(node.children.count)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Color.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .background(isSelected ? Color.bgElevated : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
                }
                .buttonStyle(.plain)

                if node.isDirectory && node.isExpanded {
                    ForEach(node.children, id: \.id) { child in
                        TreeNodeRow(
                            node: child,
                            selectedPath: selectedPath,
                            filter: filter,
                            modifiedFiles: modifiedFiles,
                            depth: depth + 1,
                            onSelect: onSelect
                        )
                    }
                }
            }
        }
    }

    private var isSelected: Bool {
        !node.isDirectory && node.fullPath == selectedPath
    }

    private var nodeIcon: String {
        if node.isDirectory { return node.isExpanded ? "folder.fill" : "folder" }
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx", "py", "rs", "go": return "chevron.left.forwardslash.chevron.right"
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "yml", "yaml", "toml": return "list.bullet.indent"
        case "html", "css": return "globe"
        case "png", "jpg", "jpeg", "svg", "gif": return "photo"
        default: return "doc.text"
        }
    }

    private var nodeIconColor: Color {
        if node.isDirectory { return Color.terminalYellow }
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 1, green: 0.45, blue: 0.25) // Swift orange
        case "ts", "tsx": return Color(red: 0.2, green: 0.5, blue: 1) // TS blue
        case "js", "jsx": return Color.terminalYellow
        case "py": return Color(red: 0.3, green: 0.6, blue: 0.9)
        case "rs": return Color(red: 0.87, green: 0.4, blue: 0.2) // Rust orange
        case "md": return Color.terminalCyan
        case "json", "yml", "yaml", "toml": return Color.statusSuccess
        default: return Color.textTertiary
        }
    }
}

// MARK: - RenderedContentView — Rendering engine

/// Decides how to render file content based on file extension:
/// - `.md` → Rendered markdown
/// - Code files → Syntax-highlighted with line numbers
/// - Other → Plain monospaced text
struct RenderedContentView: View {
    let content: String
    let fileName: String

    var body: some View {
        let ext = (fileName as NSString).pathExtension.lowercased()

        if ext == "md" || ext == "markdown" {
            MarkdownRendererView(markdown: content)
        } else if SyntaxHighlighter.supportedExtensions.contains(ext) {
            SyntaxHighlightedView(content: content, language: ext)
        } else {
            // Plain text with line numbers
            PlainTextWithLineNumbers(content: content)
        }
    }
}

// MARK: - PlainTextWithLineNumbers

struct PlainTextWithLineNumbers: View {
    let content: String

    var body: some View {
        let lines = content.components(separatedBy: "\n")
        let gutterWidth = CGFloat(String(lines.count).count) * 8 + 16

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(idx + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textTertiary.opacity(0.4))
                        .frame(width: gutterWidth, alignment: .trailing)
                        .padding(.trailing, 8)

                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(.vertical, 0.5)
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - SyntaxHighlighter — Lightweight token-based syntax highlighting

struct SyntaxHighlighter {
    static let supportedExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go",
        "java", "c", "cpp", "h", "hpp", "cs", "rb", "sh", "bash",
        "html", "css", "json", "yml", "yaml", "toml", "sql",
    ]

    enum TokenType {
        case keyword, string, comment, number, type, annotation, punctuation, plain
    }

    struct Token {
        let text: String
        let type: TokenType
    }

    static func tokenize(line: String, language: String) -> [Token] {
        let keywords = keywordsFor(language: language)
        let typeKeywords = typeKeywordsFor(language: language)
        var tokens: [Token] = []
        var remaining = line[...]

        while !remaining.isEmpty {
            // Comment: // or #
            if remaining.hasPrefix("//") || (language == "py" && remaining.hasPrefix("#")) ||
               (language == "sh" || language == "bash" || language == "yml" || language == "yaml") && remaining.hasPrefix("#") {
                tokens.append(Token(text: String(remaining), type: .comment))
                break
            }

            // String: "..." or '...'
            if remaining.first == "\"" || remaining.first == "'" || remaining.first == "`" {
                let quote = remaining.first!
                var end = remaining.index(after: remaining.startIndex)
                var escaped = false
                while end < remaining.endIndex {
                    if escaped { escaped = false; end = remaining.index(after: end); continue }
                    if remaining[end] == "\\" { escaped = true; end = remaining.index(after: end); continue }
                    if remaining[end] == quote { end = remaining.index(after: end); break }
                    end = remaining.index(after: end)
                }
                tokens.append(Token(text: String(remaining[remaining.startIndex..<end]), type: .string))
                remaining = remaining[end...]
                continue
            }

            // Number
            if let first = remaining.first, first.isNumber || (first == "." && remaining.count > 1 && remaining[remaining.index(after: remaining.startIndex)].isNumber) {
                var end = remaining.startIndex
                while end < remaining.endIndex && (remaining[end].isNumber || remaining[end] == "." || remaining[end] == "x" || remaining[end] == "_" || remaining[end].isHexDigit) {
                    end = remaining.index(after: end)
                }
                tokens.append(Token(text: String(remaining[remaining.startIndex..<end]), type: .number))
                remaining = remaining[end...]
                continue
            }

            // Annotation: @something
            if remaining.first == "@" {
                var end = remaining.index(after: remaining.startIndex)
                while end < remaining.endIndex && (remaining[end].isLetter || remaining[end].isNumber || remaining[end] == "_") {
                    end = remaining.index(after: end)
                }
                tokens.append(Token(text: String(remaining[remaining.startIndex..<end]), type: .annotation))
                remaining = remaining[end...]
                continue
            }

            // Word (identifier or keyword)
            if let first = remaining.first, first.isLetter || first == "_" {
                var end = remaining.startIndex
                while end < remaining.endIndex && (remaining[end].isLetter || remaining[end].isNumber || remaining[end] == "_") {
                    end = remaining.index(after: end)
                }
                let word = String(remaining[remaining.startIndex..<end])
                if keywords.contains(word) {
                    tokens.append(Token(text: word, type: .keyword))
                } else if typeKeywords.contains(word) || (word.first?.isUppercase == true && word.count > 1) {
                    tokens.append(Token(text: word, type: .type))
                } else {
                    tokens.append(Token(text: word, type: .plain))
                }
                remaining = remaining[end...]
                continue
            }

            // Punctuation / operator
            tokens.append(Token(text: String(remaining.first!), type: .punctuation))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return tokens
    }

    static func keywordsFor(language: String) -> Set<String> {
        switch language {
        case "swift":
            return ["import", "func", "var", "let", "if", "else", "guard", "return", "for", "while",
                    "switch", "case", "default", "struct", "class", "enum", "protocol", "extension",
                    "private", "public", "internal", "fileprivate", "open", "static", "final",
                    "async", "await", "throws", "throw", "try", "catch", "do", "in", "where",
                    "self", "Self", "super", "nil", "true", "false", "some", "any", "typealias",
                    "init", "deinit", "override", "mutating", "weak", "unowned", "lazy", "break", "continue"]
        case "ts", "tsx", "js", "jsx":
            return ["import", "export", "from", "const", "let", "var", "function", "return",
                    "if", "else", "for", "while", "switch", "case", "default", "break", "continue",
                    "class", "extends", "implements", "interface", "type", "enum", "new", "this",
                    "async", "await", "try", "catch", "throw", "finally", "typeof", "instanceof",
                    "true", "false", "null", "undefined", "void", "of", "in", "as", "is",
                    "readonly", "private", "public", "protected", "static", "abstract", "super", "yield"]
        case "py":
            return ["import", "from", "def", "class", "return", "if", "elif", "else", "for",
                    "while", "try", "except", "finally", "raise", "with", "as", "pass", "break",
                    "continue", "and", "or", "not", "in", "is", "None", "True", "False",
                    "lambda", "yield", "global", "nonlocal", "assert", "del", "self", "async", "await"]
        case "rs":
            return ["fn", "let", "mut", "if", "else", "match", "for", "while", "loop", "return",
                    "struct", "enum", "impl", "trait", "pub", "use", "mod", "crate", "self", "super",
                    "async", "await", "move", "ref", "where", "type", "const", "static", "unsafe",
                    "true", "false", "as", "in", "dyn", "extern", "break", "continue"]
        case "go":
            return ["package", "import", "func", "var", "const", "type", "struct", "interface",
                    "if", "else", "for", "range", "switch", "case", "default", "return", "break",
                    "continue", "go", "defer", "select", "chan", "map", "nil", "true", "false",
                    "make", "new", "append", "len", "cap"]
        default:
            return ["if", "else", "for", "while", "return", "function", "class", "import", "export",
                    "true", "false", "null", "var", "let", "const", "new", "this", "self"]
        }
    }

    static func typeKeywordsFor(language: String) -> Set<String> {
        switch language {
        case "swift":
            return ["String", "Int", "Bool", "Double", "Float", "Array", "Dictionary", "Set",
                    "Optional", "Result", "Error", "URL", "Data", "Date", "UUID", "View", "Color",
                    "CGFloat", "Void", "Any", "AnyObject", "Sendable", "Codable", "Hashable", "Identifiable"]
        case "ts", "tsx", "js", "jsx":
            return ["string", "number", "boolean", "any", "void", "never", "unknown", "object",
                    "Array", "Promise", "Record", "Partial", "Required", "Readonly", "Map", "Set"]
        case "rs":
            return ["String", "Vec", "Option", "Result", "Box", "Rc", "Arc", "HashMap",
                    "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64",
                    "bool", "usize", "isize", "str", "Self"]
        case "py":
            return ["int", "str", "float", "bool", "list", "dict", "tuple", "set",
                    "Optional", "List", "Dict", "Tuple", "Set", "Any", "Union", "Type"]
        default:
            return []
        }
    }

    static func colorFor(tokenType: TokenType) -> Color {
        switch tokenType {
        case .keyword:     return Color(red: 0.83, green: 0.4, blue: 0.9)   // Purple
        case .string:      return Color(red: 0.87, green: 0.56, blue: 0.34) // Orange
        case .comment:     return Color(red: 0.42, green: 0.47, blue: 0.53) // Gray
        case .number:      return Color(red: 0.82, green: 0.77, blue: 0.47) // Yellow
        case .type:        return Color(red: 0.35, green: 0.78, blue: 0.98) // Cyan
        case .annotation:  return Color(red: 0.98, green: 0.78, blue: 0.35) // Gold
        case .punctuation: return Color(red: 0.6, green: 0.63, blue: 0.67)  // Light gray
        case .plain:       return Color.textPrimary
        }
    }
}

// MARK: - SyntaxHighlightedView

struct SyntaxHighlightedView: View {
    let content: String
    let language: String

    var body: some View {
        let lines = content.components(separatedBy: "\n")
        let gutterWidth = CGFloat(String(lines.count).count) * 8 + 16

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 0) {
                    // Line number gutter
                    Text("\(idx + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textTertiary.opacity(0.35))
                        .frame(width: gutterWidth, alignment: .trailing)
                        .padding(.trailing, 8)

                    // Highlighted line
                    highlightedLine(line)
                }
                .padding(.vertical, 0.5)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        let tokens = SyntaxHighlighter.tokenize(line: line, language: language)
        if tokens.isEmpty {
            Text(" ")
                .font(.system(size: 12, design: .monospaced))
        } else {
            tokens.reduce(Text("")) { result, token in
                result + Text(token.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(SyntaxHighlighter.colorFor(tokenType: token.type))
            }
        }
    }
}

// MARK: - MarkdownRendererView

/// Renders markdown with styled headers, bold, italic, code blocks, and lists.
struct MarkdownRendererView: View {
    let markdown: String

    /// Pre-parsed markdown blocks (code blocks collapsed into single items).
    private var blocks: [MdBlock] {
        var result: [MdBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLang = ""

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    result.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: codeLang))
                    codeLines = []
                    codeLang = ""
                } else {
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                inCodeBlock.toggle()
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                result.append(.line(line))
            }
        }
        // Flush unclosed code block
        if !codeLines.isEmpty {
            result.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: codeLang))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .line(let text):
                    markdownLine(text)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum MdBlock {
        case line(String)
        case codeBlock(code: String, language: String)
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(styledText(String(line.dropFirst(2))))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 8)
                .padding(.bottom, 2)
        } else if line.hasPrefix("## ") {
            Text(styledText(String(line.dropFirst(3))))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 6)
                .padding(.bottom, 1)
        } else if line.hasPrefix("### ") {
            Text(styledText(String(line.dropFirst(4))))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 4)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.terminalCyan)
                Text(styledText(String(line.dropFirst(2))))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.leading, 8)
        } else if line.hasPrefix("> ") {
            Text(styledText(String(line.dropFirst(2))))
                .font(.system(size: 12, design: .default))
                .foregroundStyle(Color.textTertiary)
                .italic()
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.terminalCyan.opacity(0.4))
                        .frame(width: 3)
                }
        } else if line.hasPrefix("---") || line.hasPrefix("***") {
            Divider()
                .background(Color.borderMuted)
                .padding(.vertical, 4)
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Spacer().frame(height: 6)
        } else {
            Text(styledText(line))
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// Parse inline markdown: **bold**, *italic*, `code`
    private func styledText(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[...]

        while !remaining.isEmpty {
            // Inline code: `...`
            if remaining.hasPrefix("`") {
                let after = remaining[remaining.index(after: remaining.startIndex)...]
                if let endIdx = after.firstIndex(of: "`") {
                    let code = String(after[after.startIndex..<endIdx])
                    var attr = AttributedString(code)
                    attr.font = .system(size: 11, design: .monospaced)
                    attr.foregroundColor = Color.terminalCyan
                    attr.backgroundColor = Color.bgElevated
                    result += attr
                    remaining = after[after.index(after: endIdx)...]
                    continue
                }
            }

            // Bold: **...**
            if remaining.hasPrefix("**") {
                let after = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
                if let range = after.range(of: "**") {
                    let bold = String(after[after.startIndex..<range.lowerBound])
                    var attr = AttributedString(bold)
                    attr.font = .system(size: 12, weight: .bold)
                    result += attr
                    remaining = after[range.upperBound...]
                    continue
                }
            }

            // Italic: *...*
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**") {
                let after = remaining[remaining.index(after: remaining.startIndex)...]
                if let endIdx = after.firstIndex(of: "*") {
                    let italic = String(after[after.startIndex..<endIdx])
                    var attr = AttributedString(italic)
                    attr.font = .system(size: 12).italic()
                    result += attr
                    remaining = after[after.index(after: endIdx)...]
                    continue
                }
            }

            // Plain character
            var attr = AttributedString(String(remaining.first!))
            attr.font = .system(size: 12)
            result += attr
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
    }
}

// MARK: - CodeBlockView

struct CodeBlockView: View {
    let code: String
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.bgApp)
            }

            if SyntaxHighlighter.supportedExtensions.contains(language) {
                SyntaxHighlightedView(content: code, language: language)
                    .padding(8)
            } else {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgApp)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.borderMuted.opacity(0.5), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - SplitDiffView — Side-by-side old/new comparison

/// Shows old version (left) and new version (right) side by side with
/// line-level highlighting of additions and deletions.
struct SplitDiffView: View {
    let oldContent: String
    let newContent: String
    let fileName: String

    var body: some View {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")
        let maxLines = max(oldLines.count, newLines.count)
        let gutterWidth = CGFloat(String(maxLines).count) * 8 + 12
        let useSyntax = SyntaxHighlighter.supportedExtensions.contains(ext)

        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left: OLD (HEAD)
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.statusError.opacity(0.7))
                        Text("HEAD (before)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.statusError.opacity(0.7))
                        Spacer()
                        Text("\(oldLines.count) lines")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.statusError.opacity(0.06))

                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<maxLines, id: \.self) { idx in
                                let line = idx < oldLines.count ? oldLines[idx] : ""
                                let newLine = idx < newLines.count ? newLines[idx] : ""
                                let isDiff = line != newLine

                                HStack(alignment: .top, spacing: 0) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.textTertiary.opacity(0.3))
                                        .frame(width: gutterWidth, alignment: .trailing)
                                        .padding(.trailing, 6)

                                    if useSyntax {
                                        highlightedText(line, language: ext)
                                    } else {
                                        Text(line.isEmpty ? " " : line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 0.5)
                                .padding(.horizontal, 4)
                                .background(isDiff ? Color.statusError.opacity(0.08) : Color.clear)
                            }
                        }
                        .textSelection(.enabled)
                        .padding(4)
                    }
                }
                .frame(width: geo.size.width / 2)

                // Divider
                Rectangle()
                    .fill(Color.borderMuted)
                    .frame(width: 1)

                // Right: NEW (working copy)
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.statusSuccess.opacity(0.7))
                        Text("Working copy (after)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.statusSuccess.opacity(0.7))
                        Spacer()
                        Text("\(newLines.count) lines")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.statusSuccess.opacity(0.06))

                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<maxLines, id: \.self) { idx in
                                let line = idx < newLines.count ? newLines[idx] : ""
                                let oldLine = idx < oldLines.count ? oldLines[idx] : ""
                                let isDiff = line != oldLine

                                HStack(alignment: .top, spacing: 0) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.textTertiary.opacity(0.3))
                                        .frame(width: gutterWidth, alignment: .trailing)
                                        .padding(.trailing, 6)

                                    if useSyntax {
                                        highlightedText(line, language: ext)
                                    } else {
                                        Text(line.isEmpty ? " " : line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 0.5)
                                .padding(.horizontal, 4)
                                .background(isDiff ? Color.statusSuccess.opacity(0.08) : Color.clear)
                            }
                        }
                        .textSelection(.enabled)
                        .padding(4)
                    }
                }
                .frame(width: geo.size.width / 2)
            }
        }
    }

    @ViewBuilder
    private func highlightedText(_ line: String, language: String) -> some View {
        let tokens = SyntaxHighlighter.tokenize(line: line, language: language)
        if tokens.isEmpty {
            Text(" ")
                .font(.system(size: 11, design: .monospaced))
        } else {
            tokens.reduce(Text("")) { result, token in
                result + Text(token.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SyntaxHighlighter.colorFor(tokenType: token.type))
            }
        }
    }
}

// MARK: - WebPreviewView — WKWebView wrapper

struct WebPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if URL actually changed
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - DiffRendererView

struct DiffRendererView: View {
    let diff: String

    var body: some View {
        let lines = diff.components(separatedBy: "\n")
        let gutterWidth: CGFloat = 40

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(idx + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary.opacity(0.3))
                        .frame(width: gutterWidth, alignment: .trailing)
                        .padding(.trailing, 6)

                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(lineColor(line))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(lineBackground(line))
            }
        }
        .textSelection(.enabled)
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return Color.textSecondary }
        if line.hasPrefix("@@") { return Color.terminalCyan }
        if line.hasPrefix("+") { return Color.statusSuccess }
        if line.hasPrefix("-") { return Color.statusError }
        if line.hasPrefix("diff ") { return Color.terminalYellow }
        return Color.textPrimary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.statusSuccess.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.statusError.opacity(0.08) }
        return Color.clear
    }
}

// MARK: - ProposalSidebarItem

struct ProposalSidebarItem: View {
    let proposal: BrainProposal

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(riskColor)
                .frame(width: 6, height: 6)

            Image(systemName: proposalIcon)
                .font(.system(size: 10))
                .foregroundStyle(riskColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(proposal.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(proposal.type.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var proposalIcon: String {
        switch proposal.type {
        case .launch: return "play.circle.fill"
        case .suite: return "square.stack.3d.up.fill"
        case .decision: return "brain.head.profile"
        case .alert: return "exclamationmark.triangle.fill"
        }
    }

    private var riskColor: Color {
        switch proposal.riskLevel {
        case .low: return Color.statusSuccess
        case .medium: return Color.terminalYellow
        case .high: return Color.statusWarning
        case .critical: return Color.statusError
        }
    }
}

// MARK: - ProposalDetailCard

struct ProposalDetailCard: View {
    let proposal: BrainProposal
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: proposalIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(riskColor)
                Text(proposal.type.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(proposal.riskLevel.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(riskColor.opacity(0.15))
                    .clipShape(Capsule())
                Text(timeAgo(proposal.createdAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().background(Color.borderMuted)

            Text(proposal.title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            Text(proposal.detail)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.terminalCyan)
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgApp)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))

            if proposal.type == .launch {
                HStack(spacing: Theme.Spacing.md) {
                    if let agent = proposal.agentType {
                        labeledValue(label: "Agent", value: agent)
                    }
                    if let role = proposal.role {
                        labeledValue(label: "Role", value: role)
                    }
                }
            }

            if let excerpt = proposal.scannerExcerpt, !excerpt.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scanner Context")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                    Text(excerpt)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(5)
                        .padding(Theme.Spacing.xs)
                        .background(Color.bgApp)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
                }
            }

            Divider().background(Color.borderMuted)

            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onReject) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        Text("Reject").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.statusError)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                        Text("Approve").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.statusSuccess)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(riskColor.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: riskColor.opacity(0.15), radius: 6, y: 2)
    }

    @ViewBuilder
    private func labeledValue(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.bgApp)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
        }
    }

    private var proposalIcon: String {
        switch proposal.type {
        case .launch: return "play.circle.fill"
        case .suite: return "square.stack.3d.up.fill"
        case .decision: return "brain.head.profile"
        case .alert: return "exclamationmark.triangle.fill"
        }
    }

    private var riskColor: Color {
        switch proposal.riskLevel {
        case .low: return Color.statusSuccess
        case .medium: return Color.terminalYellow
        case .high: return Color.statusWarning
        case .critical: return Color.statusError
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
