import Foundation
import GRDB

// MARK: - BudgetAlert

/// Alert emitted when a budget threshold is reached or exceeded.
/// Tracks acknowledgment state for UI dismissal.
struct BudgetAlert: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var budgetConfigId: UUID
    var alertType: String
    var currentSpendCents: Int
    var budgetCents: Int
    var percentUsed: Double
    var message: String
    var acknowledged: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        budgetConfigId: UUID,
        alertType: String,
        currentSpendCents: Int,
        budgetCents: Int,
        percentUsed: Double,
        message: String,
        acknowledged: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.budgetConfigId = budgetConfigId
        self.alertType = alertType
        self.currentSpendCents = currentSpendCents
        self.budgetCents = budgetCents
        self.percentUsed = percentUsed
        self.message = message
        self.acknowledged = acknowledged
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension BudgetAlert: FetchableRecord, PersistableRecord {
    static let databaseTableName = "budget_alert"

    static let budgetConfig = belongsTo(BudgetConfig.self)

    var budgetConfig: QueryInterfaceRequest<BudgetConfig> {
        request(for: BudgetAlert.budgetConfig)
    }

    enum Columns: String, ColumnExpression {
        case id, budgetConfigId, alertType, currentSpendCents
        case budgetCents, percentUsed, message, acknowledged, createdAt
    }
}
