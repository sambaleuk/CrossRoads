import Foundation
import GRDB

// MARK: - OrgRole

/// Organizational role within a cockpit session.
/// Defines the hierarchy and responsibilities for agent orchestration.
struct OrgRole: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID
    var name: String
    var roleType: String
    var parentRoleId: UUID?
    var assignedSlotId: UUID?
    var goalDescription: String?
    var skillNames: String?
    var authority: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        name: String,
        roleType: String,
        parentRoleId: UUID? = nil,
        assignedSlotId: UUID? = nil,
        goalDescription: String? = nil,
        skillNames: String? = nil,
        authority: String = "limited",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.name = name
        self.roleType = roleType
        self.parentRoleId = parentRoleId
        self.assignedSlotId = assignedSlotId
        self.goalDescription = goalDescription
        self.skillNames = skillNames
        self.authority = authority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension OrgRole: FetchableRecord, PersistableRecord {
    static let databaseTableName = "org_role"

    static let cockpitSession = belongsTo(CockpitSession.self, using: ForeignKey(["sessionId"]))
    static let assignedSlot = belongsTo(AgentSlot.self, using: ForeignKey(["assignedSlotId"]))
    static let parentRole = belongsTo(OrgRole.self, using: ForeignKey(["parentRoleId"]))
    static let childRoles = hasMany(OrgRole.self, using: ForeignKey(["parentRoleId"]))

    var cockpitSession: QueryInterfaceRequest<CockpitSession> {
        request(for: OrgRole.cockpitSession)
    }

    var assignedSlot: QueryInterfaceRequest<AgentSlot> {
        request(for: OrgRole.assignedSlot)
    }

    var childRoles: QueryInterfaceRequest<OrgRole> {
        request(for: OrgRole.childRoles)
    }

    enum Columns: String, ColumnExpression {
        case id, sessionId, name, roleType, parentRoleId
        case assignedSlotId, goalDescription, skillNames, authority
        case createdAt, updatedAt
    }
}
