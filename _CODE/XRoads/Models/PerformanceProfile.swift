import Foundation
import GRDB

// MARK: - PerformanceProfile

/// Aggregated performance profile for an agent type and task category.
/// Updated incrementally as learning records accumulate.
struct PerformanceProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var agentType: String
    var runtimeId: UUID?
    var taskCategory: String
    var totalExecutions: Int
    var successRate: Double
    var avgDurationMs: Int
    var avgCostCents: Int
    var avgFilesChanged: Double
    var avgTestPassRate: Double
    var conflictRate: Double
    var lastUpdatedAt: Date

    init(
        id: UUID = UUID(),
        agentType: String,
        runtimeId: UUID? = nil,
        taskCategory: String,
        totalExecutions: Int,
        successRate: Double,
        avgDurationMs: Int,
        avgCostCents: Int,
        avgFilesChanged: Double,
        avgTestPassRate: Double,
        conflictRate: Double,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.agentType = agentType
        self.runtimeId = runtimeId
        self.taskCategory = taskCategory
        self.totalExecutions = totalExecutions
        self.successRate = successRate
        self.avgDurationMs = avgDurationMs
        self.avgCostCents = avgCostCents
        self.avgFilesChanged = avgFilesChanged
        self.avgTestPassRate = avgTestPassRate
        self.conflictRate = conflictRate
        self.lastUpdatedAt = lastUpdatedAt
    }
}

// MARK: - GRDB Conformance

extension PerformanceProfile: FetchableRecord, PersistableRecord {
    static let databaseTableName = "performance_profile"

    static let agentRuntime = belongsTo(AgentRuntime.self, using: ForeignKey(["runtimeId"]))

    var agentRuntime: QueryInterfaceRequest<AgentRuntime> {
        request(for: PerformanceProfile.agentRuntime)
    }

    enum Columns: String, ColumnExpression {
        case id, agentType, runtimeId, taskCategory
        case totalExecutions, successRate, avgDurationMs, avgCostCents
        case avgFilesChanged, avgTestPassRate, conflictRate, lastUpdatedAt
    }
}
