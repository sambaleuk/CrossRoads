import Foundation
import GRDB

// MARK: - ExecutionGateStatus

/// Maps to ExecutionGateLifecycle states from states.json
enum ExecutionGateStatus: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case pending
    case dryRun = "dry_run"
    case awaitingApproval = "awaiting_approval"
    case executing
    case completed
    case rejected
    case rolledBack = "rolled_back"
}

// MARK: - RiskLevel

enum RiskLevel: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case low
    case medium
    case high
    case critical
}

// MARK: - AuditEntry

/// Immutable audit entry written on gate completion or rollback
struct AuditEntry: Codable, Hashable, Sendable {
    let gateId: UUID
    let finalStatus: String
    let operationType: String
    let riskLevel: String
    let approvedBy: String?
    let deniedReason: String?
    let durationMs: Int64?
    let completedAt: Date
}

// MARK: - ExecutionGate

/// Persisted SafeExecutor gate within a cockpit session.
/// Maps to ExecutionGate entity from model.json.
struct ExecutionGate: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var agentSlotId: UUID
    var status: ExecutionGateStatus
    var operationType: String
    var operationPayload: String
    var riskLevel: String
    var estimatedImpact: String?
    var approvedBy: String?
    var approvedAt: Date?
    var deniedReason: String?
    var rollbackPayload: String?
    var auditEntry: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        agentSlotId: UUID,
        status: ExecutionGateStatus = .pending,
        operationType: String,
        operationPayload: String,
        riskLevel: String,
        estimatedImpact: String? = nil,
        approvedBy: String? = nil,
        approvedAt: Date? = nil,
        deniedReason: String? = nil,
        rollbackPayload: String? = nil,
        auditEntry: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.agentSlotId = agentSlotId
        self.status = status
        self.operationType = operationType
        self.operationPayload = operationPayload
        self.riskLevel = riskLevel
        self.estimatedImpact = estimatedImpact
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.deniedReason = deniedReason
        self.rollbackPayload = rollbackPayload
        self.auditEntry = auditEntry
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension ExecutionGate: FetchableRecord, PersistableRecord {
    static let databaseTableName = "execution_gate"

    static let agentSlot = belongsTo(AgentSlot.self)

    var agentSlot: QueryInterfaceRequest<AgentSlot> {
        request(for: ExecutionGate.agentSlot)
    }

    enum Columns: String, ColumnExpression {
        case id, agentSlotId, status, operationType, operationPayload
        case riskLevel, estimatedImpact, approvedBy, approvedAt
        case deniedReason, rollbackPayload, auditEntry, createdAt, updatedAt
    }
}
