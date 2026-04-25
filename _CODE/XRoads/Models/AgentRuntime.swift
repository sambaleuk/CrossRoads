import Foundation
import GRDB

// MARK: - AgentRuntime

/// Definition of an agent runtime (CLI, Docker, remote URL).
/// Describes how to launch and communicate with an agent backend.
struct AgentRuntime: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var runtimeType: String
    var command: String?
    var url: String?
    var dockerImage: String?
    var healthCheckCommand: String?
    var configSchema: String?
    var configDefaults: String?
    var capabilities: String
    var icon: String?
    var color: String?
    var isBuiltin: Bool
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        runtimeType: String = "cli",
        command: String? = nil,
        url: String? = nil,
        dockerImage: String? = nil,
        healthCheckCommand: String? = nil,
        configSchema: String? = nil,
        configDefaults: String? = nil,
        capabilities: String = "[]",
        icon: String? = nil,
        color: String? = nil,
        isBuiltin: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.runtimeType = runtimeType
        self.command = command
        self.url = url
        self.dockerImage = dockerImage
        self.healthCheckCommand = healthCheckCommand
        self.configSchema = configSchema
        self.configDefaults = configDefaults
        self.capabilities = capabilities
        self.icon = icon
        self.color = color
        self.isBuiltin = isBuiltin
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension AgentRuntime: FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_runtime"

    enum Columns: String, ColumnExpression {
        case id, name, runtimeType, command, url
        case dockerImage, healthCheckCommand, configSchema
        case configDefaults, capabilities, icon, color
        case isBuiltin, isEnabled, createdAt
    }
}
