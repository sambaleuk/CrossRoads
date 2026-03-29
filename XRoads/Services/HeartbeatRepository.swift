import Foundation
import GRDB
import os

// MARK: - HeartbeatRepositoryError

enum HeartbeatRepositoryError: LocalizedError {
    case heartbeatNotFound(UUID)
    case scheduledRunNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .heartbeatNotFound(let id):
            return "HeartbeatConfig not found: \(id)"
        case .scheduledRunNotFound(let id):
            return "ScheduledRun not found: \(id)"
        }
    }
}

// MARK: - HeartbeatRepository

/// Actor-based repository for HeartbeatConfig and ScheduledRun CRUD operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor HeartbeatRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "HeartbeatRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - HeartbeatConfig CRUD

    /// Create a new heartbeat configuration.
    func createHeartbeat(_ config: HeartbeatConfig) throws -> HeartbeatConfig {
        try dbQueue.write { db in
            var record = config
            try record.insert(db)
            return record
        }
    }

    /// Update pulse result: sets lastPulseAt, lastPulseResult, and resets consecutiveFailures to 0.
    func updatePulse(id: UUID, resultJson: String) throws {
        try dbQueue.write { db in
            guard var config = try HeartbeatConfig.fetchOne(db, key: id) else {
                throw HeartbeatRepositoryError.heartbeatNotFound(id)
            }
            config.lastPulseAt = Date()
            config.lastPulseResult = resultJson
            config.consecutiveFailures = 0
            config.updatedAt = Date()
            try config.update(db)
        }
    }

    /// Record a failure: increments consecutiveFailures.
    func recordFailure(id: UUID) throws {
        try dbQueue.write { db in
            guard var config = try HeartbeatConfig.fetchOne(db, key: id) else {
                throw HeartbeatRepositoryError.heartbeatNotFound(id)
            }
            config.consecutiveFailures += 1
            config.updatedAt = Date()
            try config.update(db)
        }
    }

    /// Fetch all heartbeat configs for a session.
    func fetchHeartbeats(sessionId: UUID) throws -> [HeartbeatConfig] {
        try dbQueue.read { db in
            try HeartbeatConfig
                .filter(HeartbeatConfig.Columns.sessionId == sessionId)
                .order(HeartbeatConfig.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    // MARK: - ScheduledRun CRUD

    /// Create a new scheduled run.
    func createScheduledRun(_ run: ScheduledRun) throws -> ScheduledRun {
        try dbQueue.write { db in
            var record = run
            try record.insert(db)
            return record
        }
    }

    /// Fetch all enabled scheduled runs.
    func fetchEnabledScheduledRuns() throws -> [ScheduledRun] {
        try dbQueue.read { db in
            try ScheduledRun
                .filter(ScheduledRun.Columns.enabled == true)
                .order(ScheduledRun.Columns.nextRunAt.asc)
                .fetchAll(db)
        }
    }

    /// Fetch all due runs: nextRunAt <= now AND enabled == true.
    func fetchDueRuns() throws -> [ScheduledRun] {
        try dbQueue.read { db in
            let now = Date()
            return try ScheduledRun
                .filter(ScheduledRun.Columns.enabled == true)
                .filter(ScheduledRun.Columns.nextRunAt != nil)
                .filter(ScheduledRun.Columns.nextRunAt <= now)
                .order(ScheduledRun.Columns.nextRunAt.asc)
                .fetchAll(db)
        }
    }

    /// Update run result and optionally set next run time.
    func updateRunResult(id: UUID, result: String, nextRunAt: Date?) throws {
        try dbQueue.write { db in
            guard var run = try ScheduledRun.fetchOne(db, key: id) else {
                throw HeartbeatRepositoryError.scheduledRunNotFound(id)
            }
            run.lastRunAt = Date()
            run.lastRunResult = result
            run.nextRunAt = nextRunAt
            try run.update(db)
        }
    }
}
