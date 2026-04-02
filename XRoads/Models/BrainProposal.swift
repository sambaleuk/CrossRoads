import Foundation

// MARK: - BrainProposalType

/// The type of action the brain is proposing.
enum BrainProposalType: String, Codable, Hashable, Sendable {
    case launch       // [LAUNCH:agent:role:task] — spawn a new agent slot
    case suite        // [SUITE:id] — switch active suite
    case decision     // [DECISION] — strategic decision requiring confirmation
    case alert        // [ALERT] — critical alert requiring acknowledgment
}

// MARK: - BrainProposalStatus

enum BrainProposalStatus: String, Codable, Hashable, Sendable {
    case pending       // Waiting for operator review
    case approved      // Operator approved
    case rejected      // Operator rejected
    case modified      // Operator approved with modifications
    case expired       // Timed out without response
}

// MARK: - BrainProposal

/// Represents an action proposed by the cockpit brain that requires operator approval
/// before execution. Displayed in the ReviewRibbon overlay.
struct BrainProposal: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var type: BrainProposalType
    var status: BrainProposalStatus
    var title: String               // Human-readable summary
    var detail: String              // Full proposal text / rationale
    var riskLevel: RiskLevel

    // [LAUNCH]-specific fields
    var agentType: String?          // "claude", "gemini", "codex"
    var role: String?               // "backend", "testing", "review", etc.
    var task: String?               // The specific task description

    // [SUITE]-specific fields
    var suiteId: String?            // Target suite ID

    // Context from scanner/advisor
    var scannerExcerpt: String?     // Relevant part of scanner report
    var advisorRationale: String?   // Advisor's reasoning

    var createdAt: Date
    var resolvedAt: Date?
    var resolvedBy: String?         // "operator" or "timeout"

    init(
        id: UUID = UUID(),
        type: BrainProposalType,
        status: BrainProposalStatus = .pending,
        title: String,
        detail: String,
        riskLevel: RiskLevel = .medium,
        agentType: String? = nil,
        role: String? = nil,
        task: String? = nil,
        suiteId: String? = nil,
        scannerExcerpt: String? = nil,
        advisorRationale: String? = nil,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolvedBy: String? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.title = title
        self.detail = detail
        self.riskLevel = riskLevel
        self.agentType = agentType
        self.role = role
        self.task = task
        self.suiteId = suiteId
        self.scannerExcerpt = scannerExcerpt
        self.advisorRationale = advisorRationale
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
    }

    /// Create a proposal from a parsed [LAUNCH:agent:role:task] command.
    static func fromLaunch(agentType: String, role: String, task: String) -> BrainProposal {
        let risk: RiskLevel = {
            let lower = role.lowercased()
            if lower.contains("security") || lower.contains("devops") || lower.contains("deploy") {
                return .high
            }
            if lower.contains("debug") || lower.contains("review") {
                return .medium
            }
            return .low
        }()

        return BrainProposal(
            type: .launch,
            title: "Launch \(agentType) as \(role)",
            detail: task,
            riskLevel: risk,
            agentType: agentType,
            role: role,
            task: task
        )
    }

    /// Create a proposal from a [SUITE:id] command.
    static func fromSuiteSwitch(suiteId: String) -> BrainProposal {
        BrainProposal(
            type: .suite,
            title: "Switch to \(suiteId) suite",
            detail: "Brain wants to change the active mission suite to \(suiteId).",
            riskLevel: .low,
            suiteId: suiteId
        )
    }
}
