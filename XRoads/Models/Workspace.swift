import Foundation
import GRDB

// MARK: - Workspace

/// A workspace groups project paths with visual settings and resource limits.
/// Supports multiple active workspaces with per-workspace budget caps.
struct Workspace: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var projectPath: String
    var color: String
    var icon: String?
    var isActive: Bool
    var maxSlots: Int
    var totalBudgetCents: Int?
    var metadata: String?
    var lastAccessedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        color: String = "#0DF170",
        icon: String? = nil,
        isActive: Bool = false,
        maxSlots: Int = 6,
        totalBudgetCents: Int? = nil,
        metadata: String? = nil,
        lastAccessedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.color = color
        self.icon = icon
        self.isActive = isActive
        self.maxSlots = maxSlots
        self.totalBudgetCents = totalBudgetCents
        self.metadata = metadata
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension Workspace: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workspace"

    enum Columns: String, ColumnExpression {
        case id, name, projectPath, color, icon
        case isActive, maxSlots, totalBudgetCents
        case metadata, lastAccessedAt, createdAt
    }
}
