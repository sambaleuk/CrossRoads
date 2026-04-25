import Foundation
import GRDB
import os

// MARK: - TrustScoreRepositoryError

enum TrustScoreRepositoryError: LocalizedError {
    case trustNotFound(String, String)

    var errorDescription: String? {
        switch self {
        case .trustNotFound(let agent, let domain):
            return "TrustScore not found for agent: \(agent), domain: \(domain)"
        }
    }
}

// MARK: - TrustScoreRepository

/// Actor-based repository for TrustScore computation, storage, and auto-merge policy.
/// All database access is serialized through GRDB's DatabaseQueue.
actor TrustScoreRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "TrustScoreRepo")
    private let dbQueue: DatabaseQueue
    private let learningRepository: LearningRepository

    init(dbQueue: DatabaseQueue, learningRepository: LearningRepository) {
        self.dbQueue = dbQueue
        self.learningRepository = learningRepository
    }

    // MARK: - Compute Trust

    /// Compute trust score for an agent type and domain from historical learning records.
    ///
    /// Formula: (successRate * 0.4) + (testPassRate * 0.3) + (1 - conflictRate) * 0.2 + min(total/50, 1.0) * 0.1
    func computeTrust(agentType: String, domain: String) throws -> TrustScore {
        let allRecords = try dbQueue.read { db in
            try LearningRecord
                .filter(LearningRecord.Columns.agentType == agentType)
                .fetchAll(db)
        }

        // Filter records matching the domain based on file pattern categorization
        let domainRecords = allRecords.filter { record in
            categorizeFromPatterns(record.filePatterns) == domain
        }

        let totalStories = domainRecords.count
        let successfulStories = domainRecords.filter(\.success).count
        let totalTestsPassed = domainRecords.reduce(0) { $0 + $1.testsPassed }
        let totalTestsFailed = domainRecords.reduce(0) { $0 + $1.testsFailed }
        let totalConflicts = domainRecords.reduce(0) { $0 + $1.conflictsEncountered }

        let successRate: Double = totalStories > 0 ? Double(successfulStories) / Double(totalStories) : 0.0
        let totalTests = totalTestsPassed + totalTestsFailed
        let testPassRate: Double = totalTests > 0 ? Double(totalTestsPassed) / Double(totalTests) : 1.0
        let conflictRate: Double = totalStories > 0 ? Double(totalConflicts) / Double(totalStories) : 0.0
        let volumeFactor = min(Double(totalStories) / 50.0, 1.0)

        let score = (successRate * 0.4) + (testPassRate * 0.3) + (1.0 - conflictRate) * 0.2 + volumeFactor * 0.1

        // Upsert: update existing or insert new
        return try dbQueue.write { db in
            var existing = try TrustScore
                .filter(TrustScore.Columns.agentType == agentType)
                .filter(TrustScore.Columns.domain == domain)
                .fetchOne(db)

            if var trust = existing {
                trust.score = score
                trust.totalStories = totalStories
                trust.successfulStories = successfulStories
                trust.totalTestsPassed = totalTestsPassed
                trust.totalTestsFailed = totalTestsFailed
                trust.lastComputedAt = Date()
                try trust.update(db)
                return trust
            } else {
                var trust = TrustScore(
                    agentType: agentType,
                    domain: domain,
                    score: score,
                    totalStories: totalStories,
                    successfulStories: successfulStories,
                    totalTestsPassed: totalTestsPassed,
                    totalTestsFailed: totalTestsFailed
                )
                try trust.insert(db)
                return trust
            }
        }
    }

    // MARK: - Fetch

    /// Fetch the trust score for a specific agent type and domain.
    func fetchTrust(agentType: String, domain: String) throws -> TrustScore? {
        try dbQueue.read { db in
            try TrustScore
                .filter(TrustScore.Columns.agentType == agentType)
                .filter(TrustScore.Columns.domain == domain)
                .fetchOne(db)
        }
    }

    /// Fetch all trust scores, ordered by score descending.
    func fetchAllTrust() throws -> [TrustScore] {
        try dbQueue.read { db in
            try TrustScore
                .order(TrustScore.Columns.score.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Auto-Merge Policy

    /// Update auto-merge settings for an agent type and domain.
    func updateAutoMerge(agentType: String, domain: String, enabled: Bool, threshold: Double) throws {
        try dbQueue.write { db in
            guard var trust = try TrustScore
                .filter(TrustScore.Columns.agentType == agentType)
                .filter(TrustScore.Columns.domain == domain)
                .fetchOne(db)
            else {
                throw TrustScoreRepositoryError.trustNotFound(agentType, domain)
            }
            trust.autoMergeEnabled = enabled
            trust.autoMergeThreshold = threshold
            try trust.update(db)
        }
    }

    /// Check whether an agent type in a domain qualifies for auto-merge.
    /// Returns true only if auto-merge is enabled AND the current score meets the threshold.
    func shouldAutoMerge(agentType: String, domain: String) throws -> Bool {
        try dbQueue.read { db in
            guard let trust = try TrustScore
                .filter(TrustScore.Columns.agentType == agentType)
                .filter(TrustScore.Columns.domain == domain)
                .fetchOne(db)
            else {
                return false
            }
            return trust.autoMergeEnabled && trust.score >= trust.autoMergeThreshold
        }
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
