import Foundation
import GRDB
import os

// MARK: - LearningRepositoryError

enum LearningRepositoryError: LocalizedError {
    case recordNotFound(UUID)
    case profileNotFound(String, String)

    var errorDescription: String? {
        switch self {
        case .recordNotFound(let id):
            return "LearningRecord not found: \(id)"
        case .profileNotFound(let agent, let task):
            return "PerformanceProfile not found for agent: \(agent), task: \(task)"
        }
    }
}

// MARK: - LearningRepository

/// Actor-based repository for LearningRecord and PerformanceProfile operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor LearningRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "LearningRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - LearningRecord CRUD

    /// Record a new learning observation.
    func recordLearning(_ record: LearningRecord) throws -> LearningRecord {
        try dbQueue.write { db in
            var rec = record
            try rec.insert(db)
            return rec
        }
    }

    /// Fetch all learning records for a session, ordered by creation time descending.
    func fetchRecords(sessionId: UUID) throws -> [LearningRecord] {
        try dbQueue.read { db in
            try LearningRecord
                .filter(LearningRecord.Columns.sessionId == sessionId)
                .order(LearningRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch all learning records across all sessions, ordered by creation time descending.
    func fetchAllRecords() throws -> [LearningRecord] {
        try dbQueue.read { db in
            try LearningRecord
                .order(LearningRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - PerformanceProfile

    /// Update performance profile with running average from a new learning record.
    /// Formula: new_avg = (old_avg * count + new_value) / (count + 1)
    /// Creates the profile if it doesn't exist yet.
    func updatePerformanceProfile(agentType: String, taskCategory: String, from record: LearningRecord) throws {
        try dbQueue.write { db in
            var profile = try PerformanceProfile
                .filter(PerformanceProfile.Columns.agentType == agentType)
                .filter(PerformanceProfile.Columns.taskCategory == taskCategory)
                .fetchOne(db)

            if var existing = profile {
                let count = Double(existing.totalExecutions)
                let newCount = count + 1

                // Running average updates
                existing.avgDurationMs = Int((Double(existing.avgDurationMs) * count + Double(record.durationMs)) / newCount)
                existing.avgCostCents = Int((Double(existing.avgCostCents) * count + Double(record.costCents)) / newCount)
                existing.avgFilesChanged = (existing.avgFilesChanged * count + Double(record.filesChanged)) / newCount

                // Success rate: running average of success (1.0 or 0.0)
                let successValue: Double = record.success ? 1.0 : 0.0
                existing.successRate = (existing.successRate * count + successValue) / newCount

                // Test pass rate from this record
                let testPassRate: Double = record.testsRun > 0
                    ? Double(record.testsPassed) / Double(record.testsRun)
                    : 1.0
                existing.avgTestPassRate = (existing.avgTestPassRate * count + testPassRate) / newCount

                // Conflict rate: running average of whether conflicts occurred
                let conflictValue: Double = record.conflictsEncountered > 0 ? 1.0 : 0.0
                existing.conflictRate = (existing.conflictRate * count + conflictValue) / newCount

                existing.totalExecutions = Int(newCount)
                existing.lastUpdatedAt = Date()
                try existing.update(db)
            } else {
                // Create new profile from first record
                let testPassRate: Double = record.testsRun > 0
                    ? Double(record.testsPassed) / Double(record.testsRun)
                    : 1.0

                var newProfile = PerformanceProfile(
                    agentType: agentType,
                    runtimeId: record.runtimeId,
                    taskCategory: taskCategory,
                    totalExecutions: 1,
                    successRate: record.success ? 1.0 : 0.0,
                    avgDurationMs: record.durationMs,
                    avgCostCents: record.costCents,
                    avgFilesChanged: Double(record.filesChanged),
                    avgTestPassRate: testPassRate,
                    conflictRate: record.conflictsEncountered > 0 ? 1.0 : 0.0
                )
                try newProfile.insert(db)
            }
        }
    }

    /// Fetch performance profile for an agent type and task category.
    func fetchProfile(agentType: String, taskCategory: String) throws -> PerformanceProfile? {
        try dbQueue.read { db in
            try PerformanceProfile
                .filter(PerformanceProfile.Columns.agentType == agentType)
                .filter(PerformanceProfile.Columns.taskCategory == taskCategory)
                .fetchOne(db)
        }
    }

    /// Fetch all performance profiles.
    func fetchAllProfiles() throws -> [PerformanceProfile] {
        try dbQueue.read { db in
            try PerformanceProfile
                .order(PerformanceProfile.Columns.agentType.asc, PerformanceProfile.Columns.taskCategory.asc)
                .fetchAll(db)
        }
    }
}
