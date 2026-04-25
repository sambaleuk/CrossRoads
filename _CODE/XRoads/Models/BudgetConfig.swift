import Foundation
import GRDB

// MARK: - BudgetConfig

/// Budget configuration for a session or individual slot.
/// Controls spending limits, warnings, and throttling behavior.
struct BudgetConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID
    var slotId: UUID?
    var budgetCents: Int
    var warningThresholdPct: Int
    var hardStopEnabled: Bool
    var throttleEnabled: Bool
    var dailyLimitCents: Int?
    var perStoryLimitCents: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        slotId: UUID? = nil,
        budgetCents: Int = 2500,
        warningThresholdPct: Int = 80,
        hardStopEnabled: Bool = true,
        throttleEnabled: Bool = true,
        dailyLimitCents: Int? = nil,
        perStoryLimitCents: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.slotId = slotId
        self.budgetCents = budgetCents
        self.warningThresholdPct = warningThresholdPct
        self.hardStopEnabled = hardStopEnabled
        self.throttleEnabled = throttleEnabled
        self.dailyLimitCents = dailyLimitCents
        self.perStoryLimitCents = perStoryLimitCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension BudgetConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "budget_config"

    static let cockpitSession = belongsTo(CockpitSession.self, using: ForeignKey(["sessionId"]))
    static let agentSlot = belongsTo(AgentSlot.self, using: ForeignKey(["slotId"]))
    static let alerts = hasMany(BudgetAlert.self, using: ForeignKey(["budgetConfigId"]))

    var cockpitSession: QueryInterfaceRequest<CockpitSession> {
        request(for: BudgetConfig.cockpitSession)
    }

    var agentSlot: QueryInterfaceRequest<AgentSlot> {
        request(for: BudgetConfig.agentSlot)
    }

    var alerts: QueryInterfaceRequest<BudgetAlert> {
        request(for: BudgetConfig.alerts)
    }

    enum Columns: String, ColumnExpression {
        case id, sessionId, slotId, budgetCents, warningThresholdPct
        case hardStopEnabled, throttleEnabled, dailyLimitCents
        case perStoryLimitCents, createdAt, updatedAt
    }
}
