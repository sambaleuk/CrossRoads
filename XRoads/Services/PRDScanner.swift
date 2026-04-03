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

/// Scans a project directory for PRD files, reads worktree PRDs and `.crossroads/status.json`
/// to merge real-time story statuses, and returns only main PRDs with up-to-date statuses.
///
/// The status merge flow:
/// 1. Agents in worktrees update their local `prd.json` (status → "complete")
/// 2. Loop scripts sync completions to `.crossroads/status.json`
/// 3. This scanner reads BOTH sources and merges the most advanced status into the main PRD
actor PRDScanner {

    private let logger = Logger(subsystem: "com.xroads", category: "PRDScanner")
    private let parser = PRDParser()

    /// Directories to skip during scan (performance + irrelevant content)
    private let excludedDirs: Set<String> = [
        ".git", "node_modules", ".build", "Build", "DerivedData",
        ".swiftpm", "Pods", "Carthage", ".next", "dist", "vendor",
        "__pycache__", ".venv", "venv", ".claude"
    ]

    private let targetPrefix = "prd"
    private let targetExtension = "json"

    /// Scans the project for PRD files, merges statuses from worktrees and status.json,
    /// and returns only the main (non-worktree) PRDs with up-to-date story statuses.
    func scan(projectPath: String) async -> [ScannedPRD] {
        let rootURL = URL(fileURLWithPath: projectPath)
        logger.info("Scanning for PRDs at \(projectPath, privacy: .public)")

        // 1. Find ALL prd*.json files (including in worktrees/ subdirectory)
        let allPRDURLs = findPRDFiles(root: rootURL)
        logger.info("Found \(allPRDURLs.count) total prd.json file(s)")

        // 2. Also scan sibling worktree directories (e.g. ProjectName-xroads-slot-*)
        let siblingPRDURLs = findSiblingWorktreePRDs(projectRoot: rootURL)
        if !siblingPRDURLs.isEmpty {
            logger.info("Found \(siblingPRDURLs.count) PRD(s) in sibling worktrees")
        }

        // 3. Separate main PRDs from worktree PRDs
        let (mainURLs, worktreeURLs) = separateMainFromWorktree(
            allURLs: allPRDURLs,
            projectRoot: rootURL
        )
        let allWorktreeURLs = worktreeURLs + siblingPRDURLs
        logger.info("Main PRDs: \(mainURLs.count), Worktree PRDs: \(allWorktreeURLs.count)")

        // 4. Parse worktree PRDs to collect story statuses
        var worktreeStatuses: [String: (status: PRDStoryStatus, completedAt: Date?)] = [:]
        for url in allWorktreeURLs {
            if let doc = try? await parser.parse(fileURL: url) {
                for story in doc.userStories {
                    let existing = worktreeStatuses[story.id]
                    if existing == nil || (existing!.status.isLessThan(story.status)) {
                        worktreeStatuses[story.id] = (story.status, story.completedAt)
                    }
                }
            }
        }
        if !worktreeStatuses.isEmpty {
            logger.info("Collected \(worktreeStatuses.count) story statuses from worktree PRDs")
        }

        // 5. Also load statuses from .crossroads/status.json (loop script sync)
        let statusFileStatuses = loadStatusFile(projectRoot: rootURL)

        // 6. Parse main PRDs, merge all status sources, and write back to disk
        var results: [ScannedPRD] = []
        let hasLiveUpdates = !worktreeStatuses.isEmpty || !statusFileStatuses.isEmpty

        for url in mainURLs {
            do {
                let originalDoc = try await parser.parse(fileURL: url)
                let mergedDoc = mergeAllStatuses(
                    document: originalDoc,
                    worktreeStatuses: worktreeStatuses,
                    statusFileStatuses: statusFileStatuses
                )

                // Write back to disk if any statuses were upgraded
                // This keeps the PRD file as the single source of truth
                if hasLiveUpdates && mergedDoc != originalDoc {
                    persistUpdatedPRD(mergedDoc, to: url)
                }

                let relativePath = url.path.replacingOccurrences(
                    of: rootURL.path + "/",
                    with: ""
                )
                results.append(ScannedPRD(
                    id: UUID(),
                    fileURL: url,
                    document: mergedDoc,
                    relativePath: relativePath,
                    discoveredAt: Date()
                ))
                logger.debug("Parsed PRD: \(mergedDoc.featureName) at \(relativePath, privacy: .public)")
            } catch {
                logger.warning("Failed to parse \(url.path, privacy: .public): \(error.localizedDescription)")
            }
        }

        // Sort: root prd.json first, then alphabetically
        results.sort { a, b in
            let aIsRoot = !a.relativePath.contains("/")
            let bIsRoot = !b.relativePath.contains("/")
            if aIsRoot != bIsRoot { return aIsRoot }
            return a.relativePath < b.relativePath
        }

        return results
    }

    // MARK: - Write-Back

    /// Persists the merged PRD document back to disk so the file stays
    /// as the single source of truth with up-to-date story statuses.
    private func persistUpdatedPRD(_ doc: PRDDocument, to url: URL) {
        do {
            let json = try doc.toJSON()
            try json.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Updated PRD on disk: \(url.lastPathComponent) (\(doc.userStories.filter { $0.status == .complete }.count)/\(doc.userStories.count) complete)")
        } catch {
            logger.warning("Failed to write back PRD \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Status Sources

    /// Loads story statuses from `.crossroads/status.json`.
    private func loadStatusFile(projectRoot: URL) -> [String: (status: PRDStoryStatus, completedAt: Date?)] {
        let statusURL = projectRoot
            .appendingPathComponent(".crossroads")
            .appendingPathComponent("status.json")

        guard FileManager.default.fileExists(atPath: statusURL.path),
              let data = try? Data(contentsOf: statusURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        // Support both { "stories": { ... } } and flat { "US-001": { ... } } formats
        let storiesDict: [String: Any]
        if let nested = root["stories"] as? [String: Any] {
            storiesDict = nested
        } else {
            storiesDict = root.filter { _, v in v is [String: Any] }
        }

        let formatter = ISO8601DateFormatter()
        var result: [String: (status: PRDStoryStatus, completedAt: Date?)] = [:]

        for (storyId, value) in storiesDict {
            guard let dict = value as? [String: Any],
                  let statusStr = dict["status"] as? String,
                  let status = PRDStoryStatus(rawValue: statusStr) else { continue }
            let completedAt = (dict["completedAt"] as? String).flatMap { formatter.date(from: $0) }
            result[storyId] = (status, completedAt)
        }

        if !result.isEmpty {
            logger.info("Loaded \(result.count) statuses from status.json")
        }
        return result
    }

    /// Merges statuses from worktree PRDs and status.json into a main PRD document.
    /// Takes the most advanced status from all sources (never downgrades).
    private func mergeAllStatuses(
        document: PRDDocument,
        worktreeStatuses: [String: (status: PRDStoryStatus, completedAt: Date?)],
        statusFileStatuses: [String: (status: PRDStoryStatus, completedAt: Date?)]
    ) -> PRDDocument {
        var doc = document
        for i in doc.userStories.indices {
            let storyId = doc.userStories[i].id
            var bestStatus = doc.userStories[i].status
            var bestCompletedAt = doc.userStories[i].completedAt

            // Check worktree source
            if let wt = worktreeStatuses[storyId], bestStatus.isLessThan(wt.status) {
                bestStatus = wt.status
                if wt.status == .complete { bestCompletedAt = wt.completedAt ?? bestCompletedAt }
            }

            // Check status.json source
            if let sf = statusFileStatuses[storyId], bestStatus.isLessThan(sf.status) {
                bestStatus = sf.status
                if sf.status == .complete { bestCompletedAt = sf.completedAt ?? bestCompletedAt }
            }

            doc.userStories[i].status = bestStatus
            doc.userStories[i].completedAt = bestCompletedAt
        }
        return doc
    }

    // MARK: - File Discovery

    /// Separates found PRD URLs into main PRDs and worktree PRDs.
    /// Worktree PRDs are those under a `worktrees/` directory.
    private func separateMainFromWorktree(
        allURLs: [URL],
        projectRoot: URL
    ) -> (main: [URL], worktree: [URL]) {
        var main: [URL] = []
        var worktree: [URL] = []

        for url in allURLs {
            let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            if relativePath.hasPrefix("worktrees/") {
                worktree.append(url)
            } else {
                main.append(url)
            }
        }
        return (main, worktree)
    }

    /// Finds PRD files in sibling worktree directories.
    /// XRoads creates worktrees as siblings: `ProjectName-xroads-slot-*`
    private func findSiblingWorktreePRDs(projectRoot: URL) -> [URL] {
        let fm = FileManager.default
        let parentDir = projectRoot.deletingLastPathComponent()
        let projectName = projectRoot.lastPathComponent

        guard let siblings = try? fm.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for sibling in siblings {
            let name = sibling.lastPathComponent
            // Match: ProjectName-xroads-slot-* pattern
            guard name.hasPrefix("\(projectName)-xroads-"),
                  name != projectName,
                  let isDir = try? sibling.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            // Check if it's a git worktree (has .git file, not .git directory)
            let gitFile = sibling.appendingPathComponent(".git")
            guard fm.fileExists(atPath: gitFile.path) else { continue }

            // Look for prd.json in this worktree root
            let prdURL = sibling.appendingPathComponent("prd.json")
            if fm.fileExists(atPath: prdURL.path) {
                found.append(prdURL)
            }
        }
        return found
    }

    /// Recursively finds all prd*.json files under the given root.
    private func findPRDFiles(root: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []

        // First pass: check root directory directly
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

        // Second pass: recurse into subdirectories (including worktrees/)
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Failed to create enumerator for \(root.path, privacy: .public)")
            return found
        }

        let rootPaths = Set(found.map(\.path))

        for case let fileURL as URL in enumerator {
            if rootPaths.contains(fileURL.path) { continue }

            let name = fileURL.lastPathComponent

            // Skip excluded directories (but NOT worktrees — we need those)
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
