import Foundation

// MARK: - ChairmanInput

/// Context package sent to cockpit-council Chairman for deliberation.
/// Assembled by ProjectContextReader from the project's git log, PRD, and open branches.
struct ChairmanInput: Codable, Hashable, Sendable {

    /// Recent git commit entries (last N commits)
    let gitLog: [GitLogEntry]

    /// All PRD summaries discovered in the project (replaces single prdSummary)
    let prdSummaries: [PRDSummary]

    /// Currently open branches in the project
    let openBranches: [String]

    /// Last cockpit session info (if any)
    let lastSession: LastSessionInfo?

    /// Project path this context was read from
    let projectPath: String

    /// Active suite ID (determines available roles and phases)
    let suiteId: String?

    /// Timestamp of context collection
    let collectedAt: Date

    /// Backward-compatible accessor: returns the first PRD summary (if any).
    var prdSummary: PRDSummary? { prdSummaries.first }

    // Codable: exclude the computed prdSummary from coding
    private enum CodingKeys: String, CodingKey {
        case gitLog, prdSummaries, openBranches, lastSession
        case projectPath, suiteId, collectedAt
    }
}

// MARK: - GitLogEntry

/// A single git commit entry for Chairman context
struct GitLogEntry: Codable, Hashable, Sendable, Identifiable {
    let sha: String
    let shortSha: String
    let message: String
    let author: String
    let date: Date

    var id: String { sha }
}

// MARK: - PRDSummary

/// Summary of a PRD for Chairman deliberation
struct PRDSummary: Codable, Hashable, Sendable {
    let featureName: String
    let status: String
    let branch: String?
    let totalStories: Int
    let pendingStories: Int
    let completedStories: Int
}

// MARK: - LastSessionInfo

/// Info about the most recent cockpit session for continuity
struct LastSessionInfo: Codable, Hashable, Sendable {
    let sessionId: UUID
    let status: String
    let chairmanBrief: String?
    let createdAt: Date
}
