import Foundation
import GRDB

// MARK: - ConfigSnapshot

/// Versioned snapshot of a configuration change.
/// Tracks who changed what, when, and why for audit purposes.
struct ConfigSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID?
    var workspaceId: UUID?
    var configType: String
    var version: Int
    var data: String
    var diff: String?
    var changedBy: String
    var changeReason: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID? = nil,
        workspaceId: UUID? = nil,
        configType: String,
        version: Int,
        data: String,
        diff: String? = nil,
        changedBy: String = "system",
        changeReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.workspaceId = workspaceId
        self.configType = configType
        self.version = version
        self.data = data
        self.diff = diff
        self.changedBy = changedBy
        self.changeReason = changeReason
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension ConfigSnapshot: FetchableRecord, PersistableRecord {
    static let databaseTableName = "config_snapshot"

    static let cockpitSession = belongsTo(CockpitSession.self, using: ForeignKey(["sessionId"]))
    static let workspace = belongsTo(Workspace.self, using: ForeignKey(["workspaceId"]))

    var cockpitSession: QueryInterfaceRequest<CockpitSession> {
        request(for: ConfigSnapshot.cockpitSession)
    }

    var workspace: QueryInterfaceRequest<Workspace> {
        request(for: ConfigSnapshot.workspace)
    }

    enum Columns: String, ColumnExpression {
        case id, sessionId, workspaceId, configType, version
        case data, diff, changedBy, changeReason, createdAt
    }
}
