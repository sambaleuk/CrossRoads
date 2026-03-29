import Foundation
import GRDB
import os

// MARK: - OrgRoleRepositoryError

enum OrgRoleRepositoryError: LocalizedError {
    case roleNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .roleNotFound(let id):
            return "OrgRole not found: \(id)"
        }
    }
}

// MARK: - OrgRoleRepository

/// Actor-based repository for OrgRole CRUD operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor OrgRoleRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "OrgRoleRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - Create

    /// Create a new organizational role.
    func createRole(_ role: OrgRole) throws -> OrgRole {
        try dbQueue.write { db in
            var record = role
            try record.insert(db)
            return record
        }
    }

    /// Alias for createRole — used by OrgChartService.
    @discardableResult
    func create(_ role: OrgRole) throws -> OrgRole {
        try createRole(role)
    }

    // MARK: - Fetch

    /// Fetch all roles for a session, ordered by creation time.
    func fetchRolesForSession(sessionId: UUID) throws -> [OrgRole] {
        try dbQueue.read { db in
            try OrgRole
                .filter(OrgRole.Columns.sessionId == sessionId)
                .order(OrgRole.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    /// Alias for fetchRolesForSession — used by OrgChartService.
    func fetchBySession(sessionId: UUID) throws -> [OrgRole] {
        try fetchRolesForSession(sessionId: sessionId)
    }

    /// Fetch child roles for a given parent role.
    func fetchChildren(parentId: UUID) throws -> [OrgRole] {
        try dbQueue.read { db in
            try OrgRole
                .filter(OrgRole.Columns.parentRoleId == parentId)
                .order(OrgRole.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    /// Find the CEO role for a session (roleType == "ceo").
    func findCEO(sessionId: UUID) throws -> OrgRole? {
        try dbQueue.read { db in
            try OrgRole
                .filter(OrgRole.Columns.sessionId == sessionId)
                .filter(OrgRole.Columns.roleType == "ceo")
                .fetchOne(db)
        }
    }

    // MARK: - Update

    /// Update an existing role.
    func updateRole(_ role: OrgRole) throws -> OrgRole {
        try dbQueue.write { db in
            var record = role
            record.updatedAt = Date()
            try record.update(db)
            return record
        }
    }

    /// Alias for updateRole — used by OrgChartService.
    @discardableResult
    func update(_ role: OrgRole) throws -> OrgRole {
        try updateRole(role)
    }

    // MARK: - Delete

    /// Delete a role by ID.
    func deleteRole(id: UUID) throws {
        try dbQueue.write { db in
            guard let role = try OrgRole.fetchOne(db, key: id) else {
                throw OrgRoleRepositoryError.roleNotFound(id)
            }
            try role.delete(db)
        }
    }
}
