import Foundation

// MARK: - SlotAssignment

/// A single slot assignment from cockpit-council Chairman output.
/// Represents the Chairman's decision for one agent slot.
struct SlotAssignment: Codable, Hashable, Sendable {
    let slotIndex: Int
    let skillName: String
    let agentType: String
    let branch: String
    let taskDescription: String

    enum CodingKeys: String, CodingKey {
        case slotIndex = "slot_index"
        case skillName = "skill_name"
        case agentType = "agent_type"
        case branch
        case taskDescription = "task_description"
    }
}

// MARK: - ChairmanOutput

/// Full output from cockpit-council Chairman deliberation.
/// Contains the Chairman's decision summary and slot assignments.
struct ChairmanOutput: Codable, Hashable, Sendable {
    let decision: String
    let summary: String
    let assignments: [SlotAssignment]

    enum CodingKeys: String, CodingKey {
        case decision
        case summary
        case assignments
    }
}
