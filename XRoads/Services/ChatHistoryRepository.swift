import Foundation
import GRDB
import os

// MARK: - ChatHistoryRepository

/// Lightweight actor for persisting chat messages and cockpit wake prompts.
/// The cockpit brain reads chat history for context; writes wake prompts for self-continuity.
actor ChatHistoryRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "ChatHistoryRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - Chat History

    /// Persist a chat message from the orchestrator conversation.
    func saveMessage(_ entry: ChatHistoryEntry) throws {
        try dbQueue.write { db in
            var rec = entry
            try rec.insert(db)
        }
    }

    /// Persist multiple messages in a single transaction.
    func saveMessages(_ entries: [ChatHistoryEntry]) throws {
        try dbQueue.write { db in
            for var entry in entries {
                try entry.insert(db)
            }
        }
    }

    /// Fetch chat history for a session, ordered chronologically.
    func fetchHistory(sessionId: UUID, limit: Int = 200) throws -> [ChatHistoryEntry] {
        try dbQueue.read { db in
            try ChatHistoryEntry
                .filter(ChatHistoryEntry.Columns.sessionId == sessionId.uuidString)
                .order(ChatHistoryEntry.Columns.createdAt.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch the most recent N messages across all sessions (for cockpit brain context).
    func fetchRecent(limit: Int = 50) throws -> [ChatHistoryEntry] {
        try dbQueue.read { db in
            try ChatHistoryEntry
                .order(ChatHistoryEntry.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
                .reversed()  // Return in chronological order
        }
    }

    /// Build a condensed chat summary for the cockpit brain's initial prompt.
    /// Returns the last N user messages + assistant responses, formatted as markdown.
    func buildChatSummary(sessionId: UUID?, maxMessages: Int = 30) throws -> String {
        let messages: [ChatHistoryEntry]
        if let sessionId {
            messages = try fetchHistory(sessionId: sessionId, limit: maxMessages)
        } else {
            messages = try fetchRecent(limit: maxMessages)
        }

        guard !messages.isEmpty else {
            return "No chat history available."
        }

        var lines: [String] = ["## Recent Chat History"]
        for msg in messages {
            let role = msg.role == "user" ? "USER" : msg.role == "assistant" ? "ASSISTANT" : "SYSTEM"
            let truncated = msg.content.count > 500
                ? String(msg.content.prefix(500)) + "..."
                : msg.content
            lines.append("[\(role)] \(truncated)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Wake Prompts

    /// Store a wake prompt (cockpit brain writes this before shutdown).
    func saveWakePrompt(_ prompt: CockpitWakePrompt) throws {
        try dbQueue.write { db in
            var rec = prompt
            try rec.insert(db)
        }
    }

    /// Fetch the most recent wake prompt (used at cockpit brain startup).
    func fetchLatestWakePrompt(sessionId: UUID? = nil) throws -> CockpitWakePrompt? {
        try dbQueue.read { db in
            var query = CockpitWakePrompt
                .order(CockpitWakePrompt.Columns.createdAt.desc)
                .limit(1)

            if let sessionId {
                query = CockpitWakePrompt
                    .filter(CockpitWakePrompt.Columns.sessionId == sessionId.uuidString)
                    .order(CockpitWakePrompt.Columns.createdAt.desc)
                    .limit(1)
            }

            return try query.fetchOne(db)
        }
    }

    /// Build the cockpit brain's wake-up context from the latest prompt + chat history.
    func buildWakeContext(sessionId: UUID?) throws -> String {
        var sections: [String] = []

        // Previous wake prompt (self-continuity)
        if let wake = try fetchLatestWakePrompt(sessionId: sessionId) {
            sections.append("## Previous Session State")
            sections.append(wake.prompt)

            if let obs = wake.observations {
                sections.append("\n### Observations")
                sections.append(obs)
            }
            if let pending = wake.pendingActions {
                sections.append("\n### Pending Actions")
                sections.append(pending)
            }
            if let slots = wake.slotSummaries {
                sections.append("\n### Slot Progress at Shutdown")
                sections.append(slots)
            }
        }

        // Recent chat context
        let chatSummary = try buildChatSummary(sessionId: sessionId, maxMessages: 30)
        if !chatSummary.contains("No chat history") {
            sections.append("\n" + chatSummary)
        }

        // Pending harness improvements from previous sessions
        let harnessSummary = try buildHarnessSummary()
        if !harnessSummary.isEmpty {
            sections.append("\n" + harnessSummary)
        }

        return sections.isEmpty
            ? "First session — no previous context."
            : sections.joined(separator: "\n")
    }

    // MARK: - Harness Iterations (Meta-Harness Self-Improvement)

    /// Store a harness improvement proposal from the cockpit brain.
    func saveHarnessIteration(_ iteration: HarnessIteration) throws {
        try dbQueue.write { db in
            var rec = iteration
            try rec.insert(db)
        }
    }

    /// Fetch unapplied harness proposals (for the next session to apply).
    func fetchPendingProposals(limit: Int = 20) throws -> [HarnessIteration] {
        try dbQueue.read { db in
            try HarnessIteration
                .filter(HarnessIteration.Columns.applied == false)
                .order(HarnessIteration.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Mark a proposal as applied and optionally record its impact.
    func markApplied(id: UUID, impact: String? = nil) throws {
        try dbQueue.write { db in
            if var iteration = try HarnessIteration.fetchOne(db, key: id.uuidString) {
                iteration.applied = true
                iteration.impact = impact
                try iteration.update(db)
            }
        }
    }

    /// Fetch all proposals for a target (e.g., "skill:prd") to see evolution.
    func fetchProposalsForTarget(_ target: String, limit: Int = 10) throws -> [HarnessIteration] {
        try dbQueue.read { db in
            try HarnessIteration
                .filter(HarnessIteration.Columns.target == target)
                .order(HarnessIteration.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Build a summary of pending improvements for the cockpit brain's wake context.
    func buildHarnessSummary() throws -> String {
        let pending = try fetchPendingProposals(limit: 10)
        guard !pending.isEmpty else { return "" }

        var lines = ["## Pending Self-Improvements (\(pending.count) proposals)"]
        for p in pending {
            lines.append("- **\(p.target)**: \(p.critique.prefix(120))")
        }
        lines.append("\nReview these proposals. Apply if still valid, discard if outdated.")
        return lines.joined(separator: "\n")
    }
}
