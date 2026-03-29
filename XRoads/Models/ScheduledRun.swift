import Foundation
import GRDB

// MARK: - ScheduledRun

/// A scheduled or triggered run configuration.
/// Supports cron-based scheduling, manual triggers, and webhook triggers.
struct ScheduledRun: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var projectPath: String
    var prdPath: String
    var cronExpression: String?
    var triggerType: String
    var triggerConfig: String?
    var roleTemplateName: String?
    var budgetPreset: String?
    var enabled: Bool
    var lastRunAt: Date?
    var lastRunResult: String?
    var nextRunAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectPath: String,
        prdPath: String,
        cronExpression: String? = nil,
        triggerType: String = "manual",
        triggerConfig: String? = nil,
        roleTemplateName: String? = nil,
        budgetPreset: String? = nil,
        enabled: Bool = true,
        lastRunAt: Date? = nil,
        lastRunResult: String? = nil,
        nextRunAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.prdPath = prdPath
        self.cronExpression = cronExpression
        self.triggerType = triggerType
        self.triggerConfig = triggerConfig
        self.roleTemplateName = roleTemplateName
        self.budgetPreset = budgetPreset
        self.enabled = enabled
        self.lastRunAt = lastRunAt
        self.lastRunResult = lastRunResult
        self.nextRunAt = nextRunAt
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension ScheduledRun: FetchableRecord, PersistableRecord {
    static let databaseTableName = "scheduled_run"

    enum Columns: String, ColumnExpression {
        case id, projectPath, prdPath, cronExpression, triggerType
        case triggerConfig, roleTemplateName, budgetPreset, enabled
        case lastRunAt, lastRunResult, nextRunAt, createdAt
    }
}
