import Foundation
import GRDB
import os

// MARK: - BudgetRepositoryError

enum BudgetRepositoryError: LocalizedError {
    case configNotFound(UUID)
    case alertNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .configNotFound(let id):
            return "BudgetConfig not found: \(id)"
        case .alertNotFound(let id):
            return "BudgetAlert not found: \(id)"
        }
    }
}

// MARK: - BudgetRepository

/// Actor-based repository for BudgetConfig and BudgetAlert CRUD operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor BudgetRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "BudgetRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - BudgetConfig CRUD

    /// Create a new budget configuration.
    func createConfig(_ config: BudgetConfig) throws -> BudgetConfig {
        try dbQueue.write { db in
            var record = config
            try record.insert(db)
            return record
        }
    }

    /// Fetch budget config for a session, optionally scoped to a slot.
    /// When slotId is nil, returns the session-level config.
    func fetchConfig(sessionId: UUID, slotId: UUID?) throws -> BudgetConfig? {
        try dbQueue.read { db in
            var request = BudgetConfig
                .filter(BudgetConfig.Columns.sessionId == sessionId)

            if let slotId = slotId {
                request = request.filter(BudgetConfig.Columns.slotId == slotId)
            } else {
                request = request.filter(BudgetConfig.Columns.slotId == nil)
            }

            return try request.fetchOne(db)
        }
    }

    /// Fetch the session-level budget config (slotId == nil).
    func fetchConfigForSession(sessionId: UUID) throws -> BudgetConfig? {
        try fetchConfig(sessionId: sessionId, slotId: nil)
    }

    /// Fetch the budget config scoped to a specific slot.
    func fetchConfigForSlot(slotId: UUID) throws -> BudgetConfig? {
        try dbQueue.read { db in
            try BudgetConfig
                .filter(BudgetConfig.Columns.slotId == slotId)
                .fetchOne(db)
        }
    }

    /// Update an existing budget configuration.
    @discardableResult
    func updateConfig(_ config: BudgetConfig) throws -> BudgetConfig {
        try dbQueue.write { db in
            var record = config
            record.updatedAt = Date()
            try record.update(db)
            return record
        }
    }

    // MARK: - BudgetAlert CRUD

    /// Create a new budget alert.
    func createAlert(_ alert: BudgetAlert) throws -> BudgetAlert {
        try dbQueue.write { db in
            var record = alert
            try record.insert(db)
            return record
        }
    }

    /// Fetch all alerts for a budget config, ordered by creation time descending.
    func fetchAlerts(configId: UUID) throws -> [BudgetAlert] {
        try dbQueue.read { db in
            try BudgetAlert
                .filter(BudgetAlert.Columns.budgetConfigId == configId)
                .order(BudgetAlert.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Acknowledge an alert by setting acknowledged = true.
    func acknowledgeAlert(id: UUID) throws {
        try dbQueue.write { db in
            guard var alert = try BudgetAlert.fetchOne(db, key: id) else {
                throw BudgetRepositoryError.alertNotFound(id)
            }
            alert.acknowledged = true
            try alert.update(db)
        }
    }
}
