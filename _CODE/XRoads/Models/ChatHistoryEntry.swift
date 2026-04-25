import Foundation
import GRDB

// MARK: - ChatHistoryEntry

/// Persisted chat message from the orchestrator conversation (left panel).
/// Enables the cockpit brain to access conversation context and self-continuity.
struct ChatHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID?
    var role: String          // "user", "assistant", "system"
    var content: String
    var mode: String?         // "api", "terminal", "artDirector"
    var metadata: String?     // JSON string — actions, PRD refs, etc.
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID? = nil,
        role: String,
        content: String,
        mode: String? = nil,
        metadata: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.mode = mode
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension ChatHistoryEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat_history"

    enum Columns: String, ColumnExpression {
        case id, sessionId, role, content, mode, metadata, createdAt
    }
}

// MARK: - CockpitWakePrompt

/// Self-continuity record: the cockpit brain writes this before shutdown
/// so the next session starts with full awareness of what was happening.
struct CockpitWakePrompt: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID?
    var prompt: String            // The constructed wake-up prompt
    var observations: String?     // JSON — what the cockpit observed
    var pendingActions: String?   // JSON — actions it was about to take
    var slotSummaries: String?    // JSON — per-slot progress at shutdown
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID? = nil,
        prompt: String,
        observations: String? = nil,
        pendingActions: String? = nil,
        slotSummaries: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.prompt = prompt
        self.observations = observations
        self.pendingActions = pendingActions
        self.slotSummaries = slotSummaries
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension CockpitWakePrompt: FetchableRecord, PersistableRecord {
    static let databaseTableName = "cockpit_wake_prompt"

    enum Columns: String, ColumnExpression {
        case id, sessionId, prompt, observations, pendingActions, slotSummaries, createdAt
    }
}

// MARK: - HarnessIteration

/// A self-improvement proposal from the cockpit brain (Meta-Harness pattern).
/// After each session, the brain critiques its own harnais (skills, prompts, assignments)
/// and proposes modifications. Applied proposals improve future sessions.
struct HarnessIteration: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID?
    var target: String          // "skill:prd", "chairman:prompt", "agent-def:slot-1", "loop:config"
    var critique: String        // What went wrong or could be improved
    var proposal: String        // The proposed modification (diff-like or full replacement)
    var applied: Bool
    var impact: String?         // JSON — measured result after application
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID? = nil,
        target: String,
        critique: String,
        proposal: String,
        applied: Bool = false,
        impact: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.target = target
        self.critique = critique
        self.proposal = proposal
        self.applied = applied
        self.impact = impact
        self.createdAt = createdAt
    }
}

extension HarnessIteration: FetchableRecord, PersistableRecord {
    static let databaseTableName = "harness_iteration"

    enum Columns: String, ColumnExpression {
        case id, sessionId, target, critique, proposal, applied, impact, createdAt
    }
}
