import Foundation
import os

// MARK: - CockpitViewModel

/// Drives the Cockpit Mode UI. Manages session lifecycle and slot display state.
/// Uses @Observable for SwiftUI reactivity (requires macOS 14+).
@MainActor
@Observable
final class CockpitViewModel {

    // MARK: - Published State

    /// Current cockpit session (nil when no session active)
    var session: CockpitSession?

    /// Slots for the active session, ordered by slotIndex
    var slots: [AgentSlot] = []

    /// Slots that have been revealed by sequential animation
    var revealedSlotIds: Set<UUID> = []

    /// Whether the cockpit is loading (activation in progress)
    var isLoading: Bool = false

    /// Error message to display
    var errorMessage: String?

    /// Convenience: session status or .idle when no session
    var sessionStatus: CockpitSessionStatus {
        session?.status ?? .idle
    }

    /// Whether cockpit mode is active (session exists and not idle/closed)
    var isActive: Bool {
        guard let session else { return false }
        return session.status != .idle && session.status != .closed
    }

    // MARK: - Dependencies

    private let lifecycleManager: CockpitLifecycleManager
    private let conductorService: ConductorService
    private let repository: CockpitSessionRepository
    private let logger = Logger(subsystem: "com.xroads", category: "CockpitVM")

    // MARK: - Init

    init(
        lifecycleManager: CockpitLifecycleManager,
        conductorService: ConductorService,
        repository: CockpitSessionRepository
    ) {
        self.lifecycleManager = lifecycleManager
        self.conductorService = conductorService
        self.repository = repository
    }

    // MARK: - Activate Cockpit Mode

    /// Starts the full cockpit activation flow: idle → initializing → active.
    /// Sequential slot reveal animation is driven by `revealedSlotIds`.
    func activate(projectPath: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Step 1: Create session in idle state
            let newSession = try await repository.createSession(
                CockpitSession(projectPath: projectPath)
            )
            session = newSession

            // Step 2: Activate (idle → initializing) with context reading
            let (initializing, chairmanInput) = try await lifecycleManager.activate(session: newSession)
            session = initializing

            // Step 3: Conductor deliberation (initializing → active)
            let (activeSession, assignedSlots) = try await conductorService.conductSlotAssignment(
                session: initializing,
                chairmanInput: chairmanInput
            )
            session = activeSession
            slots = assignedSlots

            // Step 4: Sequential slot reveal animation (500ms between each)
            await revealSlotsSequentially(assignedSlots)

            isLoading = false
            logger.info("Cockpit activated with \(assignedSlots.count) slots")
        } catch {
            isLoading = false
            let msg = error.localizedDescription
            errorMessage = msg
            logger.error("Cockpit activation failed: \(msg)")
        }
    }

    // MARK: - Pause (active → paused)

    /// Pauses the cockpit session and all agent slots.
    func pause() async {
        guard let current = session, current.status == .active else { return }

        do {
            let paused = try await lifecycleManager.pause(session: current)
            session = paused

            // Transition all running slots to paused
            var updatedSlots: [AgentSlot] = []
            for var slot in slots {
                if slot.status == .running {
                    slot.status = .paused
                    slot.updatedAt = Date()
                    let persisted = try await repository.updateSlot(slot)
                    updatedSlots.append(persisted)
                } else {
                    updatedSlots.append(slot)
                }
            }
            slots = updatedSlots

            logger.info("Cockpit paused: all running slots suspended")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Pause failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Resume (paused → active)

    /// Resumes the cockpit session and all paused agent slots.
    func resume() async {
        guard let current = session, current.status == .paused else { return }

        do {
            let active = try await lifecycleManager.resume(session: current)
            session = active

            // Transition all paused slots back to running
            var updatedSlots: [AgentSlot] = []
            for var slot in slots {
                if slot.status == .paused {
                    slot.status = .running
                    slot.updatedAt = Date()
                    let persisted = try await repository.updateSlot(slot)
                    updatedSlots.append(persisted)
                } else {
                    updatedSlots.append(slot)
                }
            }
            slots = updatedSlots

            logger.info("Cockpit resumed: all paused slots restarted")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Resume failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Close (active|paused → closed)

    /// Closes the cockpit session and terminates all slots.
    func close() async {
        guard let current = session,
              current.status == .active || current.status == .paused else { return }

        do {
            let closed = try await lifecycleManager.close(session: current)
            session = closed
            slots = []
            revealedSlotIds = []

            logger.info("Cockpit session closed")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Close failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Existing Session

    /// Loads an existing non-closed session for a project path (e.g., on app restart).
    func loadExistingSession(projectPath: String) async {
        do {
            if let existing = try await repository.activeSession(for: projectPath) {
                session = existing
                slots = try await repository.fetchSlots(sessionId: existing.id)
                // All existing slots are already revealed
                revealedSlotIds = Set(slots.map(\.id))
            }
        } catch {
            logger.error("Failed to load existing session: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// Reveals slots one by one with a spring animation delay.
    private func revealSlotsSequentially(_ slotsToReveal: [AgentSlot]) async {
        for slot in slotsToReveal {
            try? await Task.sleep(for: .milliseconds(500))
            revealedSlotIds.insert(slot.id)
        }
    }
}
