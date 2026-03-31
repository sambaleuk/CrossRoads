import Foundation
import GRDB

// MARK: - CockpitSessionStatus

/// Maps to CockpitLifecycle states from states.json
enum CockpitSessionStatus: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case idle
    case initializing
    case active
    case paused
    case closed
}

// MARK: - CockpitSession

/// Persisted cockpit session. Aggregate root for orchestration mode.
/// Maps to CockpitSession entity from model.json.
struct CockpitSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var projectPath: String
    var status: CockpitSessionStatus
    var chairmanBrief: String?
    var suiteId: String?       // Active suite: "developer", "marketer", "researcher", "ops"
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectPath: String,
        status: CockpitSessionStatus = .idle,
        chairmanBrief: String? = nil,
        suiteId: String? = "developer",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.status = status
        self.chairmanBrief = chairmanBrief
        self.suiteId = suiteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Returns the active Suite configuration.
    var suite: Suite {
        Suite.builtIn.first(where: { $0.id == suiteId }) ?? .developer
    }
}

// MARK: - GRDB Conformance

extension CockpitSession: FetchableRecord, PersistableRecord {
    static let databaseTableName = "cockpit_session"

    static let slots = hasMany(AgentSlot.self)

    var slots: QueryInterfaceRequest<AgentSlot> {
        request(for: CockpitSession.slots)
    }

    enum Columns: String, ColumnExpression {
        case id, projectPath, status, chairmanBrief, suiteId, createdAt, updatedAt
    }
}
