import Foundation
import os

// MARK: - ScannedPRD

/// A PRD found on disk by the scanner, with its file path and parsed document.
struct ScannedPRD: Identifiable, Sendable, Hashable {
    let id: UUID
    let fileURL: URL
    let document: PRDDocument
    let relativePath: String
    let discoveredAt: Date

    /// Short display name: feature name or filename
    var displayName: String {
        document.featureName.isEmpty
            ? fileURL.lastPathComponent
            : document.featureName
    }

    /// Story completion progress (0.0–1.0)
    var progress: Double {
        guard !document.userStories.isEmpty else { return 0 }
        let completed = document.userStories.filter { $0.status == .complete }.count
        return Double(completed) / Double(document.userStories.count)
    }

    /// Number of pending stories
    var pendingStories: Int {
        document.userStories.filter { $0.status != .complete }.count
    }

    /// Number of completed stories
    var completedStories: Int {
        document.userStories.filter { $0.status == .complete }.count
    }

    /// Convert to PRDSummary for chairman context
    func toSummary() -> PRDSummary {
        PRDSummary(
            featureName: document.featureName,
            status: document.userStories.allSatisfy({ $0.status == .complete }) ? "complete" : "in_progress",
            branch: nil,
            totalStories: document.userStories.count,
            pendingStories: pendingStories,
            completedStories: completedStories
        )
    }

    // MARK: - Hashable

    static func == (lhs: ScannedPRD, rhs: ScannedPRD) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - PRDScanner

/// Scans a project directory recursively for all prd.json files.
actor PRDScanner {

    private let logger = Logger(subsystem: "com.xroads", category: "PRDScanner")
    private let parser = PRDParser()

    /// Directories to skip during scan (performance + relevance)
    private let excludedDirs: Set<String> = [
        ".git", "node_modules", ".build", "Build", "DerivedData",
        ".swiftpm", "Pods", "Carthage", ".next", "dist", "vendor",
        "__pycache__", ".venv", "venv"
    ]

    /// File name prefix to match (prd.json, prd-feature.json, etc.)
    private let targetPrefix = "prd"
    private let targetExtension = "json"

    /// Scans the given project root for all prd.json files.
    /// - Parameter projectPath: Absolute path to the project root
    /// - Returns: Array of successfully parsed PRDs
    func scan(projectPath: String) async -> [ScannedPRD] {
        let rootURL = URL(fileURLWithPath: projectPath)
        logger.info("Scanning for PRDs at \(projectPath, privacy: .public)")

        let prdURLs = findPRDFiles(root: rootURL)
        logger.info("Found \(prdURLs.count) prd.json file(s)")

        var results: [ScannedPRD] = []

        for url in prdURLs {
            do {
                let doc = try await parser.parse(fileURL: url)
                let relativePath = url.path.replacingOccurrences(
                    of: rootURL.path + "/",
                    with: ""
                )
                let scanned = ScannedPRD(
                    id: UUID(),
                    fileURL: url,
                    document: doc,
                    relativePath: relativePath,
                    discoveredAt: Date()
                )
                results.append(scanned)
                logger.debug("Parsed PRD: \(doc.featureName) at \(relativePath, privacy: .public)")
            } catch {
                logger.warning("Failed to parse \(url.path, privacy: .public): \(error.localizedDescription)")
            }
        }

        // Sort: root prd.json first, then alphabetically by path
        results.sort { a, b in
            let aIsRoot = !a.relativePath.contains("/")
            let bIsRoot = !b.relativePath.contains("/")
            if aIsRoot != bIsRoot { return aIsRoot }
            return a.relativePath < b.relativePath
        }

        return results
    }

    // MARK: - Private

    /// Recursively finds all prd*.json files under the given root.
    private func findPRDFiles(root: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []

        // First pass: check root directory directly (fast, avoids enumerator issues)
        if let rootContents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in rootContents {
                let name = fileURL.lastPathComponent.lowercased()
                if name.hasPrefix(targetPrefix) && name.hasSuffix(".\(targetExtension)") {
                    found.append(fileURL)
                }
            }
        }

        // Second pass: recurse into subdirectories
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Failed to create enumerator for \(root.path, privacy: .public)")
            return found
        }

        // Track root-level files already found to avoid duplicates
        let rootPaths = Set(found.map(\.path))

        for case let fileURL as URL in enumerator {
            // Skip files already found at root level
            if rootPaths.contains(fileURL.path) { continue }

            let name = fileURL.lastPathComponent

            // Skip excluded directories
            if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDir, excludedDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            // Match prd*.json
            let lower = name.lowercased()
            if lower.hasPrefix(targetPrefix) && lower.hasSuffix(".\(targetExtension)") {
                found.append(fileURL)
            }
        }

        logger.info("findPRDFiles found \(found.count) file(s) under \(root.path, privacy: .public)")
        return found
    }
}
