import Foundation
import GRDB
import os

// MARK: - AgentMemoryRepositoryError

enum AgentMemoryRepositoryError: LocalizedError {
    case memoryNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .memoryNotFound(let id):
            return "AgentMemory not found: \(id)"
        }
    }
}

// MARK: - AgentMemoryRepository

/// Actor-based repository for AgentMemory persistence and retrieval.
/// All database access is serialized through GRDB's DatabaseQueue.
actor AgentMemoryRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "AgentMemoryRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - Store

    /// Store a new memory entry.
    func storeMemory(_ memory: AgentMemory) throws -> AgentMemory {
        try dbQueue.write { db in
            var rec = memory
            try rec.insert(db)
            return rec
        }
    }

    // MARK: - Recall

    /// Recall memories for a specific agent type and domain, ordered by confidence and access count.
    func recallMemories(agentType: String, domain: String, limit: Int = 20) throws -> [AgentMemory] {
        try dbQueue.read { db in
            try AgentMemory
                .filter(AgentMemory.Columns.agentType == agentType)
                .filter(AgentMemory.Columns.domain == domain)
                .order(AgentMemory.Columns.confidence.desc, AgentMemory.Columns.accessCount.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Search

    /// Search memories by content or tags matching a query string.
    func searchMemories(query: String) throws -> [AgentMemory] {
        let pattern = "%\(query)%"
        return try dbQueue.read { db in
            try AgentMemory
                .filter(AgentMemory.Columns.content.like(pattern) || AgentMemory.Columns.tags.like(pattern))
                .order(AgentMemory.Columns.confidence.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Record Access

    /// Increment access count and update last accessed timestamp.
    func recordAccess(id: UUID) throws {
        try dbQueue.write { db in
            guard var memory = try AgentMemory.fetchOne(db, key: id.uuidString) else {
                throw AgentMemoryRepositoryError.memoryNotFound(id)
            }
            memory.accessCount += 1
            memory.lastAccessedAt = Date()
            try memory.update(db)
        }
    }

    // MARK: - Forget Old

    /// Delete memories older than the specified number of days. Returns count of deleted rows.
    @discardableResult
    func forgetOld(olderThanDays: Int) throws -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date())!
        return try dbQueue.write { db in
            try AgentMemory
                .filter(AgentMemory.Columns.createdAt < cutoff)
                .deleteAll(db)
        }
    }

    // MARK: - Auto-Extract Memories

    /// Automatically extract memory entries from a batch of learning records.
    /// Identifies struggles, slow tasks, and conflict patterns.
    func autoExtractMemories(sessionId: UUID, records: [LearningRecord]) throws -> [AgentMemory] {
        guard !records.isEmpty else { return [] }

        var extracted: [AgentMemory] = []

        // Compute average duration across all records
        let totalDuration = records.reduce(0) { $0 + $1.durationMs }
        let avgDuration = Double(totalDuration) / Double(records.count)

        for record in records {
            let category = categorizeFromPatterns(record.filePatterns)

            // If tests failed → "struggled with {category}"
            if record.testsFailed > 0 {
                let memory = AgentMemory(
                    agentType: record.agentType,
                    domain: category,
                    memoryType: "observation",
                    content: "struggled with \(category)",
                    confidence: min(1.0, Double(record.testsFailed) / Double(max(1, record.testsRun))),
                    sourceSessionId: sessionId,
                    sourceStoryId: record.storyId,
                    tags: "[\"test_failure\", \"\(category)\"]"
                )
                extracted.append(memory)
            }

            // If duration > 3x average → "slow on {category}"
            if Double(record.durationMs) > avgDuration * 3.0 {
                let memory = AgentMemory(
                    agentType: record.agentType,
                    domain: category,
                    memoryType: "observation",
                    content: "slow on \(category)",
                    confidence: 0.6,
                    sourceSessionId: sessionId,
                    sourceStoryId: record.storyId,
                    tags: "[\"slow\", \"\(category)\"]"
                )
                extracted.append(memory)
            }

            // If conflicts > 0 → "conflicts in {filePatterns}"
            if record.conflictsEncountered > 0 {
                let memory = AgentMemory(
                    agentType: record.agentType,
                    domain: category,
                    memoryType: "observation",
                    content: "conflicts in \(record.filePatterns)",
                    confidence: 0.7,
                    sourceSessionId: sessionId,
                    sourceStoryId: record.storyId,
                    tags: "[\"conflict\", \"\(category)\"]"
                )
                extracted.append(memory)
            }
        }

        // Persist all extracted memories
        var stored: [AgentMemory] = []
        for memory in extracted {
            let saved = try storeMemory(memory)
            stored.append(saved)
        }

        if !stored.isEmpty {
            logger.info("Auto-extracted \(stored.count) memories from \(records.count) records in session \(sessionId)")
        }

        return stored
    }

    // MARK: - Private Helpers

    /// Simple category extraction from file patterns JSON string.
    private func categorizeFromPatterns(_ filePatterns: String) -> String {
        let lower = filePatterns.lowercased()
        if lower.contains(".swift") { return "ios_swift" }
        if lower.contains(".rs") || lower.contains(".toml") { return "backend_rust" }
        if lower.contains(".ts") || lower.contains(".tsx") { return "frontend_react" }
        if lower.contains(".sql") { return "db_migration" }
        if lower.contains(".yml") || lower.contains(".yaml") { return "devops" }
        if lower.contains(".md") { return "docs" }
        return "general"
    }
}
