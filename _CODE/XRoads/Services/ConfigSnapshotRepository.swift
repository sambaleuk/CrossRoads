import Foundation
import GRDB
import os

// MARK: - ConfigSnapshotRepository

/// Actor-based repository for ConfigSnapshot CRUD operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor ConfigSnapshotRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "ConfigSnapshotRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - Create

    /// Create a new snapshot with auto-calculated version.
    /// Version is MAX(version) + 1 for the same sessionId + configType combination.
    func createSnapshot(_ snapshot: ConfigSnapshot) throws -> ConfigSnapshot {
        try dbQueue.write { db in
            // Calculate next version number
            let maxVersion = try ConfigSnapshot
                .filter(ConfigSnapshot.Columns.sessionId == snapshot.sessionId)
                .filter(ConfigSnapshot.Columns.configType == snapshot.configType)
                .select(max(ConfigSnapshot.Columns.version))
                .asRequest(of: Int?.self)
                .fetchOne(db) ?? 0

            var record = snapshot
            record.version = (maxVersion ?? 0) + 1
            try record.insert(db)
            return record
        }
    }

    // MARK: - Fetch

    /// Fetch all snapshots for a session and config type, ordered by version descending.
    func fetchSnapshots(sessionId: UUID, configType: String) throws -> [ConfigSnapshot] {
        try dbQueue.read { db in
            try ConfigSnapshot
                .filter(ConfigSnapshot.Columns.sessionId == sessionId)
                .filter(ConfigSnapshot.Columns.configType == configType)
                .order(ConfigSnapshot.Columns.version.desc)
                .fetchAll(db)
        }
    }

    /// Fetch a specific snapshot by session, config type, and version number.
    func fetchByVersion(sessionId: UUID, configType: String, version: Int) throws -> ConfigSnapshot? {
        try dbQueue.read { db in
            try ConfigSnapshot
                .filter(ConfigSnapshot.Columns.sessionId == sessionId)
                .filter(ConfigSnapshot.Columns.configType == configType)
                .filter(ConfigSnapshot.Columns.version == version)
                .fetchOne(db)
        }
    }

    /// Get the latest snapshot for a session and config type.
    func getLatest(sessionId: UUID, configType: String) throws -> ConfigSnapshot? {
        try dbQueue.read { db in
            try ConfigSnapshot
                .filter(ConfigSnapshot.Columns.sessionId == sessionId)
                .filter(ConfigSnapshot.Columns.configType == configType)
                .order(ConfigSnapshot.Columns.version.desc)
                .fetchOne(db)
        }
    }
}
