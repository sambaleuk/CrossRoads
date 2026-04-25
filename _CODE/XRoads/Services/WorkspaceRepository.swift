import Foundation
import GRDB
import os

// MARK: - WorkspaceRepositoryError

enum WorkspaceRepositoryError: LocalizedError {
    case workspaceNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        }
    }
}

// MARK: - WorkspaceRepository

/// Actor-based repository for Workspace CRUD operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor WorkspaceRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "WorkspaceRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - Create

    /// Create a new workspace.
    func createWorkspace(_ ws: Workspace) throws -> Workspace {
        try dbQueue.write { db in
            var record = ws
            try record.insert(db)
            return record
        }
    }

    // MARK: - Fetch

    /// Fetch all workspaces, ordered by last accessed time descending.
    func fetchAll() throws -> [Workspace] {
        try dbQueue.read { db in
            try Workspace
                .order(Workspace.Columns.lastAccessedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch the currently active workspace.
    func fetchActive() throws -> Workspace? {
        try dbQueue.read { db in
            try Workspace
                .filter(Workspace.Columns.isActive == true)
                .fetchOne(db)
        }
    }

    // MARK: - Switch Active

    /// Switch active workspace: deactivate all, then activate the specified one.
    func switchActive(id: UUID) throws {
        try dbQueue.write { db in
            // Deactivate all workspaces
            try db.execute(
                sql: "UPDATE workspace SET isActive = 0"
            )

            // Activate the target workspace
            guard var ws = try Workspace.fetchOne(db, key: id) else {
                throw WorkspaceRepositoryError.workspaceNotFound(id)
            }
            ws.isActive = true
            ws.lastAccessedAt = Date()
            try ws.update(db)
        }
    }

    // MARK: - Update

    /// Update an existing workspace.
    func updateWorkspace(_ ws: Workspace) throws -> Workspace {
        try dbQueue.write { db in
            var record = ws
            record.lastAccessedAt = Date()
            try record.update(db)
            return record
        }
    }

    // MARK: - Delete

    /// Delete a workspace by ID.
    func deleteWorkspace(id: UUID) throws {
        try dbQueue.write { db in
            guard let ws = try Workspace.fetchOne(db, key: id) else {
                throw WorkspaceRepositoryError.workspaceNotFound(id)
            }
            try ws.delete(db)
        }
    }
}
