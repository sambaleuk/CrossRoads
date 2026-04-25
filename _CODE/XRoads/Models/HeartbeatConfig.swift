import Foundation
import GRDB

// MARK: - HeartbeatConfig

/// Heartbeat monitoring configuration for a session or slot.
/// Tracks pulse intervals, failure counts, and health status.
struct HeartbeatConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID
    var slotId: UUID?
    var intervalMs: Int
    var enabled: Bool
    var lastPulseAt: Date?
    var lastPulseResult: String?
    var consecutiveFailures: Int
    var maxFailures: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        slotId: UUID? = nil,
        intervalMs: Int = 30000,
        enabled: Bool = true,
        lastPulseAt: Date? = nil,
        lastPulseResult: String? = nil,
        consecutiveFailures: Int = 0,
        maxFailures: Int = 5,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.slotId = slotId
        self.intervalMs = intervalMs
        self.enabled = enabled
        self.lastPulseAt = lastPulseAt
        self.lastPulseResult = lastPulseResult
        self.consecutiveFailures = consecutiveFailures
        self.maxFailures = maxFailures
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension HeartbeatConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "heartbeat_config"

    static let cockpitSession = belongsTo(CockpitSession.self, using: ForeignKey(["sessionId"]))
    static let agentSlot = belongsTo(AgentSlot.self, using: ForeignKey(["slotId"]))

    var cockpitSession: QueryInterfaceRequest<CockpitSession> {
        request(for: HeartbeatConfig.cockpitSession)
    }

    var agentSlot: QueryInterfaceRequest<AgentSlot> {
        request(for: HeartbeatConfig.agentSlot)
    }

    enum Columns: String, ColumnExpression {
        case id, sessionId, slotId, intervalMs, enabled
        case lastPulseAt, lastPulseResult, consecutiveFailures
        case maxFailures, createdAt, updatedAt
    }
}
