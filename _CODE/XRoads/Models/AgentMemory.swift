import Foundation
import GRDB

// MARK: - AgentMemory

/// Persistent memory entry for an agent, capturing observations, patterns,
/// and learned behaviors across sessions.
struct AgentMemory: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var agentType: String
    var domain: String
    var memoryType: String
    var content: String
    var confidence: Double
    var sourceSessionId: UUID?
    var sourceStoryId: String?
    var tags: String
    var accessCount: Int
    var lastAccessedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        agentType: String,
        domain: String,
        memoryType: String = "observation",
        content: String,
        confidence: Double = 0.5,
        sourceSessionId: UUID? = nil,
        sourceStoryId: String? = nil,
        tags: String = "[]",
        accessCount: Int = 0,
        lastAccessedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentType = agentType
        self.domain = domain
        self.memoryType = memoryType
        self.content = content
        self.confidence = confidence
        self.sourceSessionId = sourceSessionId
        self.sourceStoryId = sourceStoryId
        self.tags = tags
        self.accessCount = accessCount
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension AgentMemory: FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_memory"

    enum Columns: String, ColumnExpression {
        case id, agentType, domain, memoryType, content, confidence
        case sourceSessionId, sourceStoryId, tags
        case accessCount, lastAccessedAt, createdAt
    }
}
