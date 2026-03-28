import Foundation
import os

// MARK: - CockpitViewModel

/// Drives the Cockpit Mode UI. Manages session lifecycle, slot display state,
/// per-slot chat view models, and Chairman brief observation.
///
/// US-004: Added chatViewModels, chairmanBrief, and chairman feed subscription.
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

    /// Per-slot chat view models, keyed by slot ID
    var chatViewModels: [UUID: SlotChatViewModel] = [:]

    /// Latest chairman brief text, auto-refreshed from session
    var chairmanBrief: String? {
        session?.chairmanBrief
    }

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
    private let bus: MessageBusService
    private let ptyRunner: ProcessRunner?
    private let logger = Logger(subsystem: "com.xroads", category: "CockpitVM")

    /// Task for chairman brief polling
    private var chairmanBriefTask: Task<Void, Never>?

    // MARK: - Init

    init(
        lifecycleManager: CockpitLifecycleManager,
        conductorService: ConductorService,
        repository: CockpitSessionRepository,
        bus: MessageBusService,
        ptyRunner: ProcessRunner? = nil
    ) {
        self.lifecycleManager = lifecycleManager
        self.conductorService = conductorService
        self.repository = repository
        self.bus = bus
        self.ptyRunner = ptyRunner
    }

    // MARK: - Activate Cockpit Mode

    /// Starts the full cockpit activation flow: idle -> initializing -> active.
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

            // Step 2: Activate (idle -> initializing) with context reading
            let (initializing, chairmanInput) = try await lifecycleManager.activate(session: newSession)
            session = initializing

            // Step 3: Conductor deliberation (initializing -> active)
            let (activeSession, assignedSlots) = try await conductorService.conductSlotAssignment(
                session: initializing,
                chairmanInput: chairmanInput
            )
            session = activeSession
            slots = assignedSlots

            // Step 4: Create chat view models for each slot
            buildChatViewModels(for: assignedSlots)

            // Step 5: Sequential slot reveal animation (500ms between each)
            await revealSlotsSequentially(assignedSlots)

            // Step 6: Start chairman brief refresh loop
            startChairmanBriefRefresh()

            isLoading = false
            logger.info("Cockpit activated with \(assignedSlots.count) slots")
        } catch {
            isLoading = false
            let msg = error.localizedDescription
            errorMessage = msg
            logger.error("Cockpit activation failed: \(msg)")
        }
    }

    // MARK: - Pause (active -> paused)

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

    // MARK: - Resume (paused -> active)

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

    // MARK: - Close (active|paused -> closed)

    /// Closes the cockpit session and terminates all slots.
    func close() async {
        guard let current = session,
              current.status == .active || current.status == .paused else { return }

        do {
            let closed = try await lifecycleManager.close(session: current)
            session = closed
            slots = []
            revealedSlotIds = []

            // Cleanup chat view models and chairman refresh
            for (_, chatVM) in chatViewModels {
                chatVM.stopListening()
            }
            chatViewModels = [:]
            chairmanBriefTask?.cancel()
            chairmanBriefTask = nil

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
                // Build chat view models for loaded slots
                buildChatViewModels(for: slots)
                // Start chairman brief refresh
                startChairmanBriefRefresh()
            }
        } catch {
            logger.error("Failed to load existing session: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Chat View Models

    /// Creates a SlotChatViewModel for each slot and stores in chatViewModels.
    private func buildChatViewModels(for assignedSlots: [AgentSlot]) {
        for slot in assignedSlots {
            let chatVM = SlotChatViewModel(
                slot: slot,
                bus: bus,
                ptyRunner: ptyRunner
            )
            chatViewModels[slot.id] = chatVM
        }
    }

    // MARK: - Private: Chairman Brief Refresh

    /// Polls CockpitSession.chairmanBrief from the database every 3 seconds
    /// to detect updates from ChairmanFeedService.
    private func startChairmanBriefRefresh() {
        chairmanBriefTask?.cancel()
        chairmanBriefTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, let sessionId = self.session?.id else { break }
                do {
                    if let refreshed = try await self.repository.fetchSession(id: sessionId) {
                        if refreshed.chairmanBrief != self.session?.chairmanBrief {
                            self.session?.chairmanBrief = refreshed.chairmanBrief
                        }
                    }
                } catch {
                    // Non-fatal: chairman brief refresh failure
                }
            }
        }
    }

    // MARK: - Private: Slot Reveal

    /// Reveals slots one by one with a spring animation delay.
    private func revealSlotsSequentially(_ slotsToReveal: [AgentSlot]) async {
        for slot in slotsToReveal {
            try? await Task.sleep(for: .milliseconds(500))
            revealedSlotIds.insert(slot.id)
        }
    }
}
