import Foundation
import os

// MARK: - ConductorError

enum ConductorError: LocalizedError, Sendable {
    case sessionNotFound(UUID)
    case sessionNotInitializing(CockpitSessionStatus)
    case noSlotsAssigned
    case skillNotFound(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "CockpitSession not found: \(id)"
        case .sessionNotInitializing(let status):
            return "Session must be in initializing state, got: \(status.rawValue)"
        case .noSlotsAssigned:
            return "Chairman returned no slot assignments"
        case .skillNotFound(let name):
            return "MetierSkill not found: \(name)"
        }
    }
}

// MARK: - ConductorService

/// Orchestrates the Chairman deliberation and slot assignment flow.
///
/// Flow: ChairmanInput → cockpit-council → ChairmanOutput → AgentSlot creation → session activation
///
/// This is the core of US-003: takes the ChairmanInput (from US-002's ProjectContextReader),
/// sends it to cockpit-council, parses the SlotAssignment array, creates AgentSlot records,
/// and transitions the CockpitSession from initializing to active.
actor ConductorService {

    private let logger = Logger(subsystem: "com.xroads", category: "Conductor")
    private let councilClient: CockpitCouncilClientProtocol
    private let repository: CockpitSessionRepository
    private let lifecycleManager: CockpitLifecycleManager
    /// Phase 5: Org chart service for goal cascading (optional for backward compat)
    private let orgChartService: OrgChartService?

    init(
        councilClient: CockpitCouncilClientProtocol,
        repository: CockpitSessionRepository,
        lifecycleManager: CockpitLifecycleManager,
        orgChartService: OrgChartService? = nil
    ) {
        self.councilClient = councilClient
        self.repository = repository
        self.lifecycleManager = lifecycleManager
        self.orgChartService = orgChartService
    }

    // MARK: - Conduct Slot Assignment

    /// Sends ChairmanInput to cockpit-council, creates AgentSlots from the output,
    /// and transitions the session from initializing to active.
    ///
    /// - Parameters:
    ///   - session: The CockpitSession (must be in .initializing state)
    ///   - chairmanInput: Context package from ProjectContextReader
    /// - Returns: Tuple of (updated session, created slots)
    func conductSlotAssignment(
        session: CockpitSession,
        chairmanInput: ChairmanInput
    ) async throws -> (CockpitSession, [AgentSlot]) {
        guard session.status == .initializing else {
            throw ConductorError.sessionNotInitializing(session.status)
        }

        let sessionId = session.id
        logger.info("Conductor starting deliberation for session \(sessionId)")

        // Step 1: Send to cockpit-council Chairman
        let chairmanOutput = try await councilClient.deliberate(input: chairmanInput)

        // Validate Chairman returned at least one assignment
        guard !chairmanOutput.assignments.isEmpty else {
            throw ConductorError.noSlotsAssigned
        }

        logger.info("Chairman decided: \(chairmanOutput.decision)")

        // Step 2: Store chairman brief on the session
        var updatedSession = session
        updatedSession.chairmanBrief = chairmanOutput.summary
        updatedSession = try await repository.updateSession(updatedSession)

        // Step 3: Create AgentSlot records from assignments
        var createdSlots: [AgentSlot] = []

        for assignment in chairmanOutput.assignments {
            // Resolve or create the MetierSkill for this assignment
            let skillId = try await resolveSkill(named: assignment.skillName)

            let slot = AgentSlot(
                cockpitSessionId: sessionId,
                slotIndex: assignment.slotIndex,
                status: .empty,
                agentType: assignment.agentType,
                branchName: assignment.branch,
                skillId: skillId
            )

            let created = try await repository.createSlot(slot)
            createdSlots.append(created)

            logger.info("Created slot \(assignment.slotIndex): \(assignment.skillName) (\(assignment.agentType))")
        }

        // Step 4: Transition session to active via lifecycle manager
        let activatedSession = try await lifecycleManager.assignSlots(
            session: updatedSession,
            slots: createdSlots
        )

        logger.info("Session \(sessionId) activated with \(createdSlots.count) slots")

        // WIRING 5: Cascade goals from chairman brief through the org hierarchy
        if let orgChartService = orgChartService, let chairmanBrief = activatedSession.chairmanBrief {
            Task {
                do {
                    let cascaded = try await orgChartService.cascadeGoals(
                        sessionId: sessionId,
                        ceoGoal: chairmanBrief
                    )
                    logger.info("Goal cascading complete: \(cascaded.count) roles received goals")
                } catch {
                    logger.warning("Goal cascading failed (non-critical): \(error.localizedDescription)")
                }
            }
        }

        return (activatedSession, createdSlots)
    }

    // MARK: - Private

    /// Resolves a MetierSkill by name. Creates a placeholder if not found.
    private func resolveSkill(named name: String) async throws -> UUID {
        // Try to find existing skill in the database
        if let existing = try await repository.findSkillByName(name) {
            return existing.id
        }

        // Create a placeholder MetierSkill for this assignment
        let skill = MetierSkill(
            name: name,
            family: "cockpit-council",
            skillMdPath: "skills/\(name).md"
        )
        let created = try await repository.createSkill(skill)
        return created.id
    }
}
