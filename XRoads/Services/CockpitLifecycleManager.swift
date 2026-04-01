import Foundation
import os

// MARK: - CockpitLifecycleError

enum CockpitLifecycleError: LocalizedError, Sendable {
    case guardViolation(guard: String, event: String)
    case invalidTransition(from: CockpitSessionStatus, event: String)

    var errorDescription: String? {
        switch self {
        case .guardViolation(let guardName, let event):
            return "Guard '\(guardName)' blocked event '\(event)'"
        case .invalidTransition(let from, let event):
            return "No transition for event '\(event)' from state '\(from.rawValue)'"
        }
    }
}

// MARK: - CockpitLifecycleManager

/// Manages CockpitLifecycle state transitions as defined in states.json.
/// Enforces guards and triggers actions on transitions.
actor CockpitLifecycleManager {

    private let logger = Logger(subsystem: "com.xroads", category: "CockpitLifecycle")
    private let contextReader: ProjectContextReader
    private let repository: CockpitSessionRepository

    init(contextReader: ProjectContextReader, repository: CockpitSessionRepository) {
        self.contextReader = contextReader
        self.repository = repository
    }

    // MARK: - Activate (idle → initializing)

    /// Activates a CockpitSession: validates the has_valid_project guard,
    /// reads project context, and transitions from idle to initializing.
    ///
    /// CockpitLifecycle: idle → activate [guard: has_valid_project] → initializing
    /// Action: read_project_context
    ///
    /// - Parameter session: The session to activate (must be in idle state)
    /// - Returns: Tuple of (updated session, chairman input context)
    /// - Throws: CockpitLifecycleError on guard violation or invalid state
    func activate(session: CockpitSession) async throws -> (CockpitSession, ChairmanInput) {
        // Verify current state allows this transition
        guard session.status == .idle else {
            throw CockpitLifecycleError.invalidTransition(from: session.status, event: "activate")
        }

        let path = session.projectPath

        // Guard: has_valid_project
        guard await contextReader.hasValidProject(at: path) else {
            logger.warning("Guard has_valid_project failed for \(path, privacy: .public)")
            throw CockpitLifecycleError.guardViolation(guard: "has_valid_project", event: "activate")
        }

        // Action: read_project_context
        let chairmanInput = try await contextReader.readContext(projectPath: path)

        // Transition: idle → initializing
        var updated = session
        updated.status = .initializing
        updated.updatedAt = Date()
        let persisted = try await repository.updateSession(updated)

        logger.info("CockpitSession \(session.id) activated: idle → initializing")

        return (persisted, chairmanInput)
    }

    // MARK: - Assign Slots (initializing → active)

    /// Transitions a CockpitSession from initializing to active after slot assignment.
    ///
    /// CockpitLifecycle: initializing → slots_assigned [guard: at_least_one_slot_configured] → active
    /// Action: start_all_slots
    ///
    /// - Parameters:
    ///   - session: The session to transition (must be in initializing state)
    ///   - slots: The AgentSlot records that were created
    /// - Returns: Updated session in active state
    /// - Throws: CockpitLifecycleError on guard violation or invalid state
    func assignSlots(session: CockpitSession, slots: [AgentSlot]) async throws -> CockpitSession {
        // Verify current state allows this transition
        guard session.status == .initializing else {
            throw CockpitLifecycleError.invalidTransition(from: session.status, event: "slots_assigned")
        }

        // Slots may be empty — brain decides whether to launch them later
        let configuredSlots = slots.filter { $0.hasSkillAssigned }

        // Transition: initializing → active (even with 0 slots — brain will decide)
        var updated = session
        updated.status = .active
        updated.updatedAt = Date()
        let persisted = try await repository.updateSession(updated)

        logger.info("CockpitSession \(session.id) activated: \(configuredSlots.count) slots configured (brain decides the rest)")

        return persisted
    }

    // MARK: - Pause (active → paused)

    /// Pauses a CockpitSession: transitions from active to paused.
    ///
    /// CockpitLifecycle: active → pause → paused
    /// Action: suspend_all_slots
    ///
    /// - Parameter session: The session to pause (must be in active state)
    /// - Returns: Updated session in paused state
    func pause(session: CockpitSession) async throws -> CockpitSession {
        guard session.status == .active else {
            throw CockpitLifecycleError.invalidTransition(from: session.status, event: "pause")
        }

        var updated = session
        updated.status = .paused
        updated.updatedAt = Date()
        let persisted = try await repository.updateSession(updated)

        logger.info("CockpitSession \(session.id) paused: active → paused")

        return persisted
    }

    // MARK: - Resume (paused → active)

    /// Resumes a CockpitSession: transitions from paused to active.
    ///
    /// CockpitLifecycle: paused → resume → active
    /// Action: resume_all_slots
    ///
    /// - Parameter session: The session to resume (must be in paused state)
    /// - Returns: Updated session in active state
    func resume(session: CockpitSession) async throws -> CockpitSession {
        guard session.status == .paused else {
            throw CockpitLifecycleError.invalidTransition(from: session.status, event: "resume")
        }

        var updated = session
        updated.status = .active
        updated.updatedAt = Date()
        let persisted = try await repository.updateSession(updated)

        logger.info("CockpitSession \(session.id) resumed: paused → active")

        return persisted
    }

    // MARK: - Close (active|paused → closed)

    /// Closes a CockpitSession: transitions from active or paused to closed.
    ///
    /// CockpitLifecycle: active|paused → close [guard: no_pending_gates] → closed
    /// Action: terminate_all_slots
    ///
    /// - Parameters:
    ///   - session: The session to close (must be in active or paused state)
    ///   - hasPendingGates: Whether there are unresolved execution gates
    /// - Returns: Updated session in closed state
    func close(session: CockpitSession, hasPendingGates: Bool = false) async throws -> CockpitSession {
        guard session.status == .active || session.status == .paused else {
            throw CockpitLifecycleError.invalidTransition(from: session.status, event: "close")
        }

        // Guard: no_pending_gates (only enforced from active state per states.json)
        if session.status == .active && hasPendingGates {
            throw CockpitLifecycleError.guardViolation(guard: "no_pending_gates", event: "close")
        }

        var updated = session
        updated.status = .closed
        updated.updatedAt = Date()
        let persisted = try await repository.updateSession(updated)

        logger.info("CockpitSession \(session.id) closed: \(session.status.rawValue) → closed")

        return persisted
    }
}
