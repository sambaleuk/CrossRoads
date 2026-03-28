import Foundation
import GRDB

// MARK: - MetierSkill

/// Skill metier injectable dans un AgentSlot.
/// Defines the role, required MCPs, and SKILL.md path.
/// Maps to MetierSkill entity from model.json.
struct MetierSkill: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var family: String
    var skillMdPath: String
    var requiredMcps: String?
    var description: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        family: String,
        skillMdPath: String,
        requiredMcps: String? = nil,
        description: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.skillMdPath = skillMdPath
        self.requiredMcps = requiredMcps
        self.description = description
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension MetierSkill: FetchableRecord, PersistableRecord {
    static let databaseTableName = "metier_skill"

    enum Columns: String, ColumnExpression {
        case id, name, family, skillMdPath, requiredMcps, description, createdAt
    }
}
