import Foundation
import GRDB

// MARK: - TrustScore

/// Trust score for an agent type within a domain, derived from historical
/// execution data. Drives auto-merge policy decisions.
struct TrustScore: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var agentType: String
    var domain: String
    var score: Double
    var totalStories: Int
    var successfulStories: Int
    var totalTestsPassed: Int
    var totalTestsFailed: Int
    var autoMergeEnabled: Bool
    var autoMergeThreshold: Double
    var lastComputedAt: Date

    init(
        id: UUID = UUID(),
        agentType: String,
        domain: String,
        score: Double = 0.5,
        totalStories: Int = 0,
        successfulStories: Int = 0,
        totalTestsPassed: Int = 0,
        totalTestsFailed: Int = 0,
        autoMergeEnabled: Bool = false,
        autoMergeThreshold: Double = 0.9,
        lastComputedAt: Date = Date()
    ) {
        self.id = id
        self.agentType = agentType
        self.domain = domain
        self.score = score
        self.totalStories = totalStories
        self.successfulStories = successfulStories
        self.totalTestsPassed = totalTestsPassed
        self.totalTestsFailed = totalTestsFailed
        self.autoMergeEnabled = autoMergeEnabled
        self.autoMergeThreshold = autoMergeThreshold
        self.lastComputedAt = lastComputedAt
    }
}

// MARK: - GRDB Conformance

extension TrustScore: FetchableRecord, PersistableRecord {
    static let databaseTableName = "trust_score"

    enum Columns: String, ColumnExpression {
        case id, agentType, domain, score
        case totalStories, successfulStories
        case totalTestsPassed, totalTestsFailed
        case autoMergeEnabled, autoMergeThreshold, lastComputedAt
    }
}
