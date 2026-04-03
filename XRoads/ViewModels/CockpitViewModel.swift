import Foundation
import os

// MARK: - CockpitViewModel

/// Drives the Cockpit Mode UI. Manages session lifecycle, slot display state,
/// per-slot chat view models, and Chairman brief observation.
///
/// US-004: Added chatViewModels, chairmanBrief, and chairman feed subscription.
/// US-003: Added pendingGates, approveGate/rejectGate for approval card flow.
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

    /// US-003: Pending ExecutionGates per slot (keyed by slot ID).
    /// Only gates in `awaiting_approval` state are tracked here.
    var pendingGates: [UUID: ExecutionGate] = [:]

    /// US-003: Process IDs for slots with pending gates (keyed by slot ID).
    /// Populated by gate polling or interceptor callbacks.
    var slotProcessIds: [UUID: UUID] = [:]

    /// US-004: Whether the audit trail panel is shown
    var showAuditTrail: Bool = false

    /// Brain proposals awaiting operator approval in the Review Ribbon.
    /// Keyed by proposal ID. Only pending proposals are tracked here.
    var pendingProposals: [UUID: BrainProposal] = [:]

    /// Whether the Review Ribbon overlay is visible.
    var showReviewRibbon: Bool = false

    /// Preview URL for the Review Ribbon's browser tab.
    /// Auto-detected from agent output (localhost URLs) or set via [PREVIEW:url] protocol.
    var previewURL: String = ""

    /// Latest agent screenshot (base64 PNG data) per slot.
    var agentScreenshots: [Int: Data] = [:]

    /// Per-slot cost summaries, keyed by slot ID
    var slotCosts: [UUID: UsageSummary] = [:]

    /// Session-wide cost summary
    var sessionCost: UsageSummary = .zero

    /// Phase 5: Org chart roles for the active session
    // orgRoles removed — supplanted by Suite roles

    /// Phase 5: Session-level budget status snapshot
    var budgetStatus: BudgetStatus?

    /// Phase 5: Per-slot heartbeat pulse results, keyed by slot ID
    var heartbeatResults: [UUID: PulseResult] = [:]

    /// Phase 5: Model routing recommendation from BudgetService
    var modelRecommendation: BudgetService.ModelRecommendation?

    /// Cockpit Brain: Current orchestration plan
    var cockpitPlan: CockpitOrchestrationPlan?

    /// Cockpit Brain: Current adaptation actions
    var adaptationActions: [AdaptationAction] = []

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
    private let ptyProcessRunner: PTYProcessRunner?
    /// US-004: Exposed for AuditTrailView sheet creation
    let gateRepo: ExecutionGateRepository?
    /// Cost tracking repository
    let costRepo: CostEventRepository?
    /// Phase 5: Org chart service (optional for backward compat)
    // orgChartService removed — supplanted by Suite roles
    /// Phase 5: Budget service (optional for backward compat)
    private let budgetService: BudgetService?
    /// Phase 5: Heartbeat service (optional for backward compat)
    private let heartbeatService: HeartbeatService?
    /// Phase 5: Learning engine (optional for backward compat)
    private let learningEngine: LearningEngine?
    /// Phase 5: Config snapshot repository (optional for backward compat)
    private let configSnapshotRepo: ConfigSnapshotRepository?
    /// Phase 5: ML trainer for post-session training (optional for backward compat)
    private let mlTrainer: MLTrainer?
    /// Phase 5: Agent memory repository for post-session extraction (optional for backward compat)
    private let agentMemoryRepo: AgentMemoryRepository?
    /// Phase 5: Learning repository for recording execution metrics (optional for backward compat)
    let learningRepo: LearningRepository?
    /// Phase 5: Trust score repository for computing agent trust (optional for backward compat)
    private let trustScoreRepo: TrustScoreRepository?
    /// Chat history + wake prompts for cockpit self-continuity
    let chatHistoryRepo: ChatHistoryRepository?
    private let logger = Logger(subsystem: "com.xroads", category: "CockpitVM")

    /// Closure to get live running slots from the dashboard (AppState.terminalSlots)
    /// Set by AppState after creating the CockpitViewModel
    var liveTerminalSlots: (() -> [TerminalSlot])?

    /// PRD-S08: Claude Code native orchestrator (lazy-initialized from ptyProcessRunner)
    private var orchestrator: ClaudeCodeOrchestrator?

    /// PRD-S09: Cockpit brain headless session reference
    private var cockpitBrainSession: HeadlessSession?
    /// PRD-S09: Cockpit brain process ID for lifecycle management
    private var cockpitBrainProcessId: UUID?

    /// Task for chairman brief polling
    private var chairmanBriefTask: Task<Void, Never>?
    /// Task for pending gate polling (US-003)
    private var gatePollTask: Task<Void, Never>?
    /// Task for cost summary polling
    private var costPollTask: Task<Void, Never>?
    // orgChartTask removed — supplanted by Suite roles
    /// Phase 5: Task for heartbeat polling
    private var heartbeatTask: Task<Void, Never>?
    /// Phase 5: Task for budget polling
    private var budgetTask: Task<Void, Never>?

    // MARK: - Init

    init(
        lifecycleManager: CockpitLifecycleManager,
        conductorService: ConductorService,
        repository: CockpitSessionRepository,
        bus: MessageBusService,
        ptyRunner: ProcessRunner? = nil,
        ptyProcessRunner: PTYProcessRunner? = nil,
        gateRepo: ExecutionGateRepository? = nil,
        costRepo: CostEventRepository? = nil,
        orgChartService: Any? = nil,  // deprecated — supplanted by Suite roles
        budgetService: BudgetService? = nil,
        heartbeatService: HeartbeatService? = nil,
        learningEngine: LearningEngine? = nil,
        configSnapshotRepo: ConfigSnapshotRepository? = nil,
        mlTrainer: MLTrainer? = nil,
        agentMemoryRepo: AgentMemoryRepository? = nil,
        learningRepo: LearningRepository? = nil,
        trustScoreRepo: TrustScoreRepository? = nil,
        chatHistoryRepo: ChatHistoryRepository? = nil
    ) {
        self.lifecycleManager = lifecycleManager
        self.conductorService = conductorService
        self.repository = repository
        self.bus = bus
        self.ptyRunner = ptyRunner
        self.ptyProcessRunner = ptyProcessRunner
        self.gateRepo = gateRepo
        self.costRepo = costRepo
        // orgChartService removed
        self.budgetService = budgetService
        self.heartbeatService = heartbeatService
        self.learningEngine = learningEngine
        self.configSnapshotRepo = configSnapshotRepo
        self.mlTrainer = mlTrainer
        self.agentMemoryRepo = agentMemoryRepo
        self.learningRepo = learningRepo
        self.trustScoreRepo = trustScoreRepo
        self.chatHistoryRepo = chatHistoryRepo
    }

    // MARK: - Activate Cockpit Mode

    /// Starts the full cockpit activation flow: idle -> initializing -> active.
    /// Sequential slot reveal animation is driven by `revealedSlotIds`.
    func activate(projectPath: String, suiteId: String = "developer") async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Step 0: Try to recover an existing active session.
            // Skip sessions stuck in "initializing" — they're stale.
            if let existing = try await repository.activeSession(for: projectPath),
               existing.status == .active || existing.status == .paused {
                logger.info("Found existing session \(existing.id) — recovering")
                session = existing
                slots = try await repository.fetchSlots(sessionId: existing.id)
                revealedSlotIds = Set(slots.map(\.id))
                buildChatViewModels(for: slots)
                startChairmanBriefRefresh()
                startGatePolling()
                startCostPolling()
                startHeartbeatPolling()
                startBudgetPolling()

                // Auto-launch any slots that are still empty
                let emptySlots = slots.filter { $0.status == .empty }
                if !emptySlots.isEmpty {
                    await autoLaunchAssignedSlots(emptySlots, projectPath: projectPath)
                }

                // Start brain + safety net
                await startCockpitBrain(projectPath: projectPath)
                startBrainSafetyNet()

                isLoading = false
                logger.info("Recovered session with \(self.slots.count) slots + brain started")
                return
            }

            // Step 0b: Clean up stale sessions (initializing, closed, orphaned)
            let cleaned = try await repository.cleanupStaleSessions(projectPath: projectPath)
            if cleaned > 0 {
                logger.info("Cleaned up \(cleaned) stale session(s) for \(projectPath)")
            }

            // Step 1: Create session in idle state with active suite
            let newSession = try await repository.createSession(
                CockpitSession(projectPath: projectPath, suiteId: suiteId)
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

            // Step 5.5: Auto-launch agents in assigned slots
            await autoLaunchAssignedSlots(assignedSlots, projectPath: projectPath)

            // Step 6: Start chairman brief refresh loop
            startChairmanBriefRefresh()

            // Step 7: Start gate polling for approval cards (US-003)
            startGatePolling()

            // Step 8: Start cost summary polling
            startCostPolling()

            // Step 9: Start Phase 5 polling loops
            startHeartbeatPolling()
            startBudgetPolling()

            // Step 10 (PRD-S09): Launch cockpit brain + start safety net timer
            await startCockpitBrain(projectPath: projectPath)
            startBrainSafetyNet()

            // Step 11: Seed initial learning data so Intelligence panel shows content
            if let learningRepo = learningRepo, let sessionId = session?.id {
                Task {
                    let sampleRecord = LearningRecord(
                        sessionId: sessionId,
                        storyId: "seed-001",
                        storyTitle: "Initial codebase analysis",
                        storyComplexity: "simple",
                        agentType: "claude",
                        durationMs: 30000,
                        costCents: 50,
                        filesChanged: 0, linesAdded: 0, linesRemoved: 0,
                        testsRun: 0, testsPassed: 0, testsFailed: 0,
                        conflictsEncountered: 0, retriesNeeded: 0,
                        success: true, failureReason: nil, filePatterns: "[]"
                    )
                    let _ = try? await learningRepo.recordLearning(sampleRecord)
                    try? await learningRepo.updatePerformanceProfile(
                        agentType: "claude", taskCategory: "general", from: sampleRecord
                    )
                    logger.info("Seeded initial learning data for Intelligence panel")
                }
            }

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

        // PRD-S09: Stop cockpit brain before closing session
        await stopCockpitBrain()
        brainSafetyNetTask?.cancel()
        brainSafetyNetTask = nil
        brainHasAnnounced = false

        // Capture slots before clearing for post-session intelligence wiring
        let closedSlots = slots

        do {
            let closed = try await lifecycleManager.close(
                session: current,
                hasPendingGates: !pendingGates.isEmpty
            )
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
            gatePollTask?.cancel()
            gatePollTask = nil
            costPollTask?.cancel()
            costPollTask = nil
            // orgChartTask removed
            heartbeatTask?.cancel()
            heartbeatTask = nil
            budgetTask?.cancel()
            budgetTask = nil
            pendingGates = [:]
            slotProcessIds = [:]
            slotCosts = [:]
            sessionCost = .zero
            // orgRoles removed
            budgetStatus = nil
            heartbeatResults = [:]

            // WIRING 3: Compute trust scores for all agent types used in session
            if let trustScoreRepo = trustScoreRepo {
                Task {
                    for slot in closedSlots {
                        let taskTitle = slot.currentTask ?? ""
                        let domain = Self.categorizeDomain(from: taskTitle)
                        let _ = try? await trustScoreRepo.computeTrust(
                            agentType: slot.agentType, domain: domain
                        )
                    }
                    logger.info("Trust scores recomputed after session close")
                }
            }

            // WIRING 4: Trigger ML model re-training after session closes
            if let mlTrainer = mlTrainer {
                Task {
                    try? await mlTrainer.trainAll()
                    logger.info("ML models re-trained after session close")
                }
            }

            // Save orchestration record to history
            let completedCount = closedSlots.filter { $0.status == .done }.count
            let failedCount = closedSlots.filter { $0.status == .error }.count
            let branches = closedSlots.compactMap { $0.branchName }
            let agentMetrics = closedSlots.map { slot -> AgentRunMetric in
                AgentRunMetric(
                    agentId: "slot-\(slot.slotIndex)",
                    agentType: AgentType(rawValue: slot.agentType),
                    storiesTotal: 1,
                    storiesCompleted: slot.status == .done ? 1 : 0,
                    state: slot.status == .done ? .finished : (slot.status == .error ? .error : .idle),
                    durationSeconds: Date().timeIntervalSince(slot.createdAt),
                    lastMessage: slot.currentTask,
                    errors: slot.status == .error ? ["Agent failed"] : []
                )
            }

            let record = OrchestrationRecord(
                id: UUID(),
                startedAt: current.createdAt,
                finishedAt: Date(),
                prdName: current.chairmanBrief?.components(separatedBy: "\n").first ?? current.projectPath.components(separatedBy: "/").last ?? "Session",
                prdPath: nil,
                resultSummary: failedCount > 0 ? "Partial" : (completedCount > 0 ? "Completed" : "No agents"),
                mergedBranches: branches,
                conflicts: [],
                totalStories: closedSlots.count,
                completedStories: completedCount,
                agentMetrics: agentMetrics,
                errors: []
            )

            // Post to AppState for persistence
            NotificationCenter.default.post(
                name: .cockpitSessionRecordReady,
                object: nil,
                userInfo: ["record": record]
            )

            logger.info("Cockpit session closed — \(completedCount)/\(closedSlots.count) slots completed")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Close failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cockpit Brain Lifecycle (PRD-S09)

    /// Starts the cockpit brain Claude Code session.
    ///
    /// Generates agent definitions (cockpit-brain.md, meta-monitor.md, transverse-producer.md)
    /// and launches the brain as a long-running headless session. Output is parsed and routed
    /// to .cockpitBrainOutput notifications for the Brain panel and MCP logs.
    private func startCockpitBrain(projectPath: String) async {
        guard brainEnabled else {
            logger.info("Cockpit brain disabled in settings")
            return
        }
        guard let runner = ptyProcessRunner else {
            logger.info("No PTY runner — cockpit brain not launched (offline mode)")
            return
        }

        // Initialize orchestrator if needed
        if orchestrator == nil {
            orchestrator = ClaudeCodeOrchestrator(ptyRunner: runner)
        }

        guard let orchestrator else { return }

        do {
            // Step 0: Build wake context from chat history + previous sessions
            var wakeContext = ""
            if let chatHistoryRepo {
                wakeContext = (try? await chatHistoryRepo.buildWakeContext(sessionId: session?.id)) ?? ""
                if !wakeContext.isEmpty {
                    logger.info("Injecting wake context (\(wakeContext.count) chars) into cockpit brain")
                }
            }

            // Step 1: Generate agent definitions (with wake context + chairman brief)
            try await orchestrator.generateCockpitBrainDefinition(
                projectPath: projectPath,
                cop: cockpitPlan,
                activeSlots: slots,
                wakeContext: wakeContext.isEmpty ? nil : wakeContext,
                chairmanBrief: session?.chairmanBrief
            )

            // Step 2: Build combined slot list from cockpit slots + dashboard terminal slots
            var allActiveSlots = slots
            if let terminalSlots = liveTerminalSlots?() {
                for ts in terminalSlots where ts.status == .running {
                    // Add terminal slots not already in cockpit slots
                    let alreadyTracked = allActiveSlots.contains(where: { $0.slotIndex == ts.slotNumber - 1 })
                    if !alreadyTracked {
                        var syntheticSlot = AgentSlot(
                            cockpitSessionId: session?.id ?? UUID(),
                            slotIndex: ts.slotNumber - 1,
                            status: .running,
                            agentType: (ts.agentType ?? .claude).rawValue
                        )
                        syntheticSlot.branchName = ts.worktree?.branch
                        syntheticSlot.worktreePath = ts.worktree?.path
                        syntheticSlot.currentTask = ts.currentTask
                        allActiveSlots.append(syntheticSlot)
                    }
                }
            }

            // Launch cockpit brain session with ALL active slots
            let brainSession = try await orchestrator.launchCockpitSession(
                projectPath: projectPath,
                cop: cockpitPlan,
                activeSlots: allActiveSlots,
                onOutput: { [weak self] rawOutput in
                    self?.handleCockpitBrainRawOutput(rawOutput)
                },
                onTermination: { [weak self] exitCode in
                    self?.handleCockpitBrainTermination(exitCode: exitCode)
                },
                onSessionId: { [weak self] sessionId in
                    self?.logger.info("Cockpit brain session ID: \(sessionId)")
                }
            )

            cockpitBrainSession = brainSession
            cockpitBrainProcessId = brainSession.processId
            brainRestartCount = 0  // Reset on successful start

            // Notify observers
            NotificationCenter.default.post(name: .cockpitBrainStarted, object: nil)
            logger.info("Cockpit brain started successfully")

            // Brain will announce itself via [CHAT] in its own output — no generic message needed
            brainHasAnnounced = true
        } catch {
            // Non-fatal: cockpit works without brain session
            logger.error("Cockpit brain launch failed: \(error.localizedDescription)")
        }
    }

    /// Stops the cockpit brain session gracefully.
    /// Writes a wake prompt so the next session starts with full context.
    private func stopCockpitBrain() async {
        guard let processId = cockpitBrainProcessId, let orchestrator else {
            return
        }

        // Write wake prompt before stopping (self-continuity)
        if let chatHistoryRepo {
            let slotSummaries = slots.map { slot in
                [
                    "slot": slot.slotIndex,
                    "agent": slot.agentType,
                    "status": slot.status.rawValue,
                    "task": slot.currentTask ?? "none",
                    "branch": slot.branchName ?? "none"
                ] as [String: Any]
            }
            let slotJSON = (try? JSONSerialization.data(withJSONObject: slotSummaries))
                .flatMap { String(data: $0, encoding: .utf8) }

            let heartbeatSummary = heartbeatResults.map { (id, pulse) in
                "Slot \(id.uuidString.prefix(8)): alive=\(pulse.alive), changes=\(pulse.gitChanges), tests=\(pulse.testsPassed)/\(pulse.testsPassed + pulse.testsFailed), stories=\(pulse.storiesCompleted)"
            }.joined(separator: "\n")

            let prompt = """
            Cockpit brain shutting down. Session: \(session?.id.uuidString ?? "unknown").
            Active slots: \(slots.filter { $0.status == .running }.count)/\(slots.count).
            Budget: \(budgetStatus?.percentUsed ?? 0)% used.
            \(heartbeatSummary.isEmpty ? "No heartbeat data." : "Last heartbeats:\n\(heartbeatSummary)")
            Resume monitoring on next wake. Prioritize: check slot progress, evaluate merge readiness.
            """

            let wake = CockpitWakePrompt(
                sessionId: session?.id,
                prompt: prompt,
                observations: nil,
                pendingActions: nil,
                slotSummaries: slotJSON
            )
            try? await chatHistoryRepo.saveWakePrompt(wake)
            logger.info("Wake prompt saved for next session")
        }

        await orchestrator.stopCockpitSession(processId: processId)
        cockpitBrainSession = nil
        cockpitBrainProcessId = nil

        // Ingest harness proposals written by the brain during the session
        if let chatHistoryRepo, let projectPath = session?.projectPath {
            let proposalsPath = URL(fileURLWithPath: projectPath)
                .appendingPathComponent(".crossroads")
                .appendingPathComponent("harness-proposals.json")

            if let data = try? Data(contentsOf: proposalsPath),
               let proposals = try? JSONDecoder().decode([[String: String]].self, from: data) {
                for p in proposals {
                    guard let target = p["target"],
                          let critique = p["critique"],
                          let proposal = p["proposal"] else { continue }

                    let iteration = HarnessIteration(
                        sessionId: session?.id,
                        target: target,
                        critique: critique,
                        proposal: proposal
                    )
                    try? await chatHistoryRepo.saveHarnessIteration(iteration)
                }
                // Clean up the file after ingestion
                try? FileManager.default.removeItem(at: proposalsPath)
                logger.info("Ingested \(proposals.count) harness proposals from cockpit brain")
            }
        }

        NotificationCenter.default.post(name: .cockpitBrainStopped, object: nil)
        logger.info("Cockpit brain stopped")
    }

    /// Handles raw output from the cockpit brain stream-json, categorizes it,
    /// and posts .cockpitBrainOutput notifications.
    private func handleCockpitBrainRawOutput(_ rawOutput: String) {
        // Parse JSON lines from the raw output
        let lines = rawOutput.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Categorize the event
            guard let categorized = ClaudeCodeOrchestrator.categorizeBrainEvent(json) else {
                continue
            }

            // Post notification for Brain panel and logs
            NotificationCenter.default.post(
                name: .cockpitBrainOutput,
                object: nil,
                userInfo: [
                    "type": categorized.type,
                    "content": categorized.content,
                    "timestamp": Date()
                ]
            )
        }
    }

    /// Handles cockpit brain process termination.
    /// Tracks consecutive brain crash restarts to prevent infinite crash loops
    private var brainRestartCount = 0
    /// Whether brain has already announced itself to chat
    private var brainHasAnnounced = false
    /// Safety net timer: wake brain periodically even without events
    private var brainSafetyNetTask: Task<Void, Never>?

    /// Read brain settings from UserDefaults
    private var brainMaxCrashRestarts: Int {
        UserDefaults.standard.object(forKey: "brainMaxCrashRestarts") as? Int ?? 3
    }
    private var brainSafetyNetInterval: Int {
        // Fallback periodic check when no events fire (safety net only)
        UserDefaults.standard.object(forKey: "brainCycleDelaySeconds") as? Int ?? 300
    }
    private var brainEnabled: Bool {
        UserDefaults.standard.object(forKey: "brainEnabled") as? Bool ?? true
    }

    /// Wake the brain on-demand (event-driven). Called when something happens that
    /// the brain should know about: slot launched, slot terminated, PRD detected, etc.
    func wakeBrain(reason: String) {
        guard brainEnabled,
              session?.status == .active,
              cockpitBrainSession == nil,  // not already running
              let projectPath = session?.projectPath else { return }

        logger.info("Waking brain: \(reason)")
        NotificationCenter.default.post(
            name: .cockpitBrainOutput,
            object: nil,
            userInfo: ["type": "loop", "content": "Waking: \(reason)", "timestamp": Date()]
        )

        Task { @MainActor in
            await startCockpitBrain(projectPath: projectPath)
        }
    }

    /// Start the safety net timer — wakes brain periodically as a fallback
    private func startBrainSafetyNet() {
        brainSafetyNetTask?.cancel()
        brainSafetyNetTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.brainSafetyNetInterval ?? 300))
                guard let self, self.session?.status == .active else { continue }
                // Only wake if brain is sleeping (not already running)
                if self.cockpitBrainSession == nil {
                    self.wakeBrain(reason: "safety net periodic check")
                }
            }
        }
    }

    private func handleCockpitBrainTermination(exitCode: Int32) {
        cockpitBrainSession = nil
        cockpitBrainProcessId = nil

        NotificationCenter.default.post(name: .cockpitBrainStopped, object: nil)

        if exitCode != 0 {
            logger.warning("Cockpit brain exited with code \(exitCode)")
            NotificationCenter.default.post(
                name: .cockpitBrainOutput,
                object: nil,
                userInfo: ["type": "error", "content": "Brain exited with code \(exitCode)", "timestamp": Date()]
            )

            // Crash recovery: limited restarts
            guard let session, session.status == .active else { return }
            let maxCrash = self.brainMaxCrashRestarts
            guard brainRestartCount < maxCrash else {
                logger.error("Brain crash limit reached (\(maxCrash))")
                return
            }
            self.brainRestartCount += 1
            let attempt = self.brainRestartCount
            logger.info("Brain crashed — restarting (attempt \(attempt)/\(maxCrash))...")
            NotificationCenter.default.post(
                name: .cockpitBrainOutput,
                object: nil,
                userInfo: ["type": "decision", "content": "Brain crash restart (\(attempt)/\(maxCrash))...", "timestamp": Date()]
            )
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                await startCockpitBrain(projectPath: session.projectPath)
            }
        } else {
            // Normal exit: brain completed its scan.
            // Notify AppState so it can dispatch pending PRD stories to slots.
            self.brainRestartCount = 0
            logger.info("Brain cycle complete — checking for dispatchable work")
            NotificationCenter.default.post(
                name: .cockpitBrainOutput,
                object: nil,
                userInfo: ["type": "loop", "content": "Cycle done. Checking for pending stories to dispatch...", "timestamp": Date()]
            )

            // Signal AppState to dispatch pending work to visible slots
            if let projectPath = session?.projectPath {
                NotificationCenter.default.post(
                    name: .brainCycleDidComplete,
                    object: nil,
                    userInfo: ["projectPath": projectPath]
                )
            }
        }
    }

    // MARK: - US-003: Approve Gate

    /// Approves a pending ExecutionGate:
    /// 1. Transitions gate from awaiting_approval -> executing via state machine (guard: approved_by_human)
    /// 2. Resumes the suspended agent process (SIGCONT)
    /// 3. Transitions AgentSlot from waiting_approval -> running (gate_approved event)
    func approveGate(_ gate: ExecutionGate) async {
        guard let gateRepo else {
            logger.error("Cannot approve gate: gateRepo not available")
            return
        }

        do {
            // 1. Transition gate: awaiting_approval -> executing
            let context = ExecutionGateGuardContext(approvedByHuman: true)
            let updated = try await gateRepo.updateStatus(
                gateId: gate.id,
                event: .approve,
                context: context,
                approvedBy: "board_user"
            )

            // 2. Resume agent process via SIGCONT
            if let slot = slots.first(where: { $0.id == gate.agentSlotId }) {
                await resumeAgentProcess(for: slot)
            }

            // 3. Transition slot: waiting_approval -> running
            try await transitionSlot(id: gate.agentSlotId, to: .running)

            // 4. Remove from pending gates
            pendingGates.removeValue(forKey: gate.agentSlotId)

            logger.info("Gate \(gate.id) approved, slot \(gate.agentSlotId) resumed -> running")
            _ = updated // silence unused warning
        } catch {
            let msg = error.localizedDescription
            errorMessage = msg
            logger.error("Approve gate failed: \(msg)")
        }
    }

    // MARK: - US-003: Reject Gate

    /// Rejects a pending ExecutionGate:
    /// 1. Transitions gate from awaiting_approval -> rejected
    /// 2. Notifies agent via stdin that the operation was rejected
    /// 3. Resumes the agent process (SIGCONT) so it can continue with rejection
    /// 4. Transitions AgentSlot from waiting_approval -> running (gate_rejected event)
    func rejectGate(_ gate: ExecutionGate) async {
        guard let gateRepo else {
            logger.error("Cannot reject gate: gateRepo not available")
            return
        }

        do {
            // 1. Transition gate: awaiting_approval -> rejected
            let updated = try await gateRepo.updateStatus(
                gateId: gate.id,
                event: .reject,
                deniedReason: "Rejected by board user"
            )

            // 2. Notify agent and resume process
            if let slot = slots.first(where: { $0.id == gate.agentSlotId }) {
                // Send rejection message via stdin before resuming
                if let processId = slotProcessIds[slot.id],
                   let runner = ptyRunner as? PTYProcessRunner {
                    try? await runner.sendInput(id: processId, text: "[SAFEEXEC_REJECTED]\n")
                }
                await resumeAgentProcess(for: slot)
            }

            // 3. Transition slot: waiting_approval -> running
            try await transitionSlot(id: gate.agentSlotId, to: .running)

            // 4. Remove from pending gates
            pendingGates.removeValue(forKey: gate.agentSlotId)

            logger.info("Gate \(gate.id) rejected, slot \(gate.agentSlotId) resumed -> running")
            _ = updated
        } catch {
            let msg = error.localizedDescription
            errorMessage = msg
            logger.error("Reject gate failed: \(msg)")
        }
    }

    // MARK: - Brain Proposal Approval

    /// Adds a brain proposal to the pending queue and shows the ribbon.
    func receiveBrainProposal(_ proposal: BrainProposal) {
        pendingProposals[proposal.id] = proposal
        showReviewRibbon = true

        // Notify chat
        NotificationCenter.default.post(
            name: .cockpitBrainToChat,
            object: nil,
            userInfo: ["content": "🔔 Brain proposes: \(proposal.title) — review in ribbon"]
        )

        logger.info("Brain proposal received: \(proposal.title) [\(proposal.type.rawValue)]")
    }

    /// Approves a brain proposal and executes the corresponding action.
    func approveProposal(_ proposal: BrainProposal) async {
        var approved = proposal
        approved.status = .approved
        approved.resolvedAt = Date()
        approved.resolvedBy = "operator"
        pendingProposals.removeValue(forKey: proposal.id)

        // Auto-hide ribbon when no more proposals
        if pendingProposals.isEmpty {
            showReviewRibbon = false
        }

        // Execute the approved action
        switch proposal.type {
        case .launch:
            if let agentType = proposal.agentType,
               let role = proposal.role,
               let task = proposal.task,
               let projectPath = session?.projectPath {
                await launchSlotFromBrain(
                    agentType: agentType,
                    role: role,
                    task: task,
                    projectPath: projectPath
                )
            }

        case .suite:
            if let suiteId = proposal.suiteId {
                NotificationCenter.default.post(
                    name: .suiteSwitched,
                    object: nil,
                    userInfo: ["suiteId": suiteId]
                )
            }

        case .decision, .alert:
            // Acknowledged — notify brain
            NotificationCenter.default.post(
                name: .cockpitBrainToChat,
                object: nil,
                userInfo: ["content": "✅ Approved: \(proposal.title)"]
            )
        }

        NotificationCenter.default.post(
            name: .brainProposalApproved,
            object: nil,
            userInfo: ["proposal": approved]
        )

        logger.info("Proposal approved: \(proposal.title)")
        wakeBrain(reason: "proposal approved: \(proposal.title)")
    }

    /// Rejects a brain proposal.
    func rejectProposal(_ proposal: BrainProposal, reason: String? = nil) {
        var rejected = proposal
        rejected.status = .rejected
        rejected.resolvedAt = Date()
        rejected.resolvedBy = "operator"
        pendingProposals.removeValue(forKey: proposal.id)

        // Auto-hide ribbon when no more proposals
        if pendingProposals.isEmpty {
            showReviewRibbon = false
        }

        NotificationCenter.default.post(
            name: .brainProposalRejected,
            object: nil,
            userInfo: ["proposal": rejected]
        )

        NotificationCenter.default.post(
            name: .cockpitBrainToChat,
            object: nil,
            userInfo: ["content": "❌ Rejected: \(proposal.title)\(reason.map { " — \($0)" } ?? "")"]
        )

        logger.info("Proposal rejected: \(proposal.title)")
        wakeBrain(reason: "proposal rejected: \(proposal.title)")
    }

    /// Approves all pending proposals at once.
    func approveAllProposals() async {
        let proposals = Array(pendingProposals.values)
        for proposal in proposals {
            await approveProposal(proposal)
        }
    }

    // MARK: - US-003: Gate Polling

    /// Starts polling for pending gates on waiting_approval slots.
    /// Called when cockpit activates or when loading existing sessions.
    func startGatePolling() {
        gatePollTask?.cancel()
        gatePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.refreshPendingGates()
            }
        }
    }

    /// Fetches the latest awaiting_approval gate for each slot that is in waiting_approval state.
    private func refreshPendingGates() async {
        guard let gateRepo else { return }

        for slot in slots where slot.status == .waitingApproval {
            do {
                let gates = try await gateRepo.fetchGates(slotId: slot.id)
                if let pending = gates.first(where: { $0.status == .awaitingApproval }) {
                    pendingGates[slot.id] = pending
                }
            } catch {
                // Non-fatal: gate fetch failure
            }
        }

        // Remove stale pending gates for slots no longer in waiting_approval
        for slotId in pendingGates.keys {
            if !slots.contains(where: { $0.id == slotId && $0.status == .waitingApproval }) {
                pendingGates.removeValue(forKey: slotId)
            }
        }
    }

    // MARK: - US-003: Private Helpers

    /// Resume an agent process by sending SIGCONT via the PTY runner.
    private func resumeAgentProcess(for slot: AgentSlot) async {
        guard let runner = ptyRunner as? PTYProcessRunner,
              let processId = slotProcessIds[slot.id] else {
            logger.warning("No process ID found for slot \(slot.id) — cannot resume")
            return
        }

        if let info = await runner.getProcessInfo(id: processId) {
            let pid = info.pid
            if pid > 0 {
                kill(pid, SIGCONT)
                logger.info("SIGCONT sent to pid \(pid) for slot \(slot.id)")
            }
        }
    }

    /// Persist a slot status transition in the database and update local state.
    private func transitionSlot(id: UUID, to newStatus: AgentSlotStatus) async throws {
        if let index = slots.firstIndex(where: { $0.id == id }) {
            slots[index].status = newStatus
            slots[index].updatedAt = Date()
            _ = try await repository.updateSlot(slots[index])
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
                // Start gate polling (US-003)
                startGatePolling()
                // Start cost polling
                startCostPolling()
                // Start Phase 5 polling loops
                // orgChartRefresh removed — supplanted by Suite roles
                startHeartbeatPolling()
                startBudgetPolling()
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

    // MARK: - Cost Tracking

    /// Records a cost event for a slot. Called by loop output parsers or API clients.
    func recordCost(
        slotId: UUID,
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) async {
        guard let costRepo else { return }
        do {
            try await costRepo.recordUsage(
                slotId: slotId,
                provider: provider,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
            await refreshCosts()
        } catch {
            logger.error("Failed to record cost: \(error.localizedDescription)")
        }
    }

    /// Starts polling cost summaries every 5 seconds.
    private func startCostPolling() {
        costPollTask?.cancel()
        costPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshCosts()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Refreshes cost summaries from the database and checks budget health.
    private func refreshCosts() async {
        guard let costRepo, let sessionId = session?.id else { return }
        do {
            sessionCost = try await costRepo.summaryForSession(sessionId: sessionId)
            slotCosts = try await costRepo.breakdownForSession(sessionId: sessionId)
        } catch {
            // Non-fatal
        }

        // WIRING 5: Check budget for running slots after cost refresh
        if let budgetService = budgetService {
            for slot in slots where slot.status == .running {
                if let status = try? await budgetService.checkBudget(slotId: slot.id) {
                    if status.status == "exceeded" {
                        logger.warning("Budget exceeded for slot \(slot.id) — \(String(format: "%.1f", status.percentUsed))% used")
                    }
                }
            }
        }
    }

    // MARK: - Phase 5: Org Chart Refresh

    // Org chart removed — supplanted by Suite roles system

    // MARK: - Phase 5: Heartbeat Polling

    /// Polls heartbeat pulse results for each slot every 10 seconds.
    private func startHeartbeatPolling() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHeartbeats()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Refreshes heartbeat pulse results for all active slots.
    private func refreshHeartbeats() async {
        guard let heartbeatService else { return }
        for slot in slots where slot.status == .running || slot.status == .paused {
            if let worktreePath = slot.branchName {
                let result = await heartbeatService.createPulseResult(
                    slotId: slot.id,
                    worktreePath: worktreePath
                )
                heartbeatResults[slot.id] = result
            }
        }
    }

    // MARK: - Phase 5: Budget Polling

    /// Polls budget status for the active session every 8 seconds.
    private func startBudgetPolling() {
        budgetTask?.cancel()
        budgetTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshBudget()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    /// Refreshes the session-level budget status.
    private func refreshBudget() async {
        guard let budgetService else { return }
        let previousPercent = budgetStatus?.percentUsed ?? 0
        // Check budget for each slot and aggregate
        for slot in slots {
            do {
                let status = try await budgetService.checkBudget(slotId: slot.id)
                // Use the worst status as the session-level summary
                if budgetStatus == nil || status.percentUsed > (budgetStatus?.percentUsed ?? 0) {
                    budgetStatus = status
                }
            } catch {
                // Non-fatal: budget check failure for individual slot
            }
        }
        // WIRING 7: Snapshot budget config when usage crosses 10% thresholds
        if let currentPercent = budgetStatus?.percentUsed,
           let sessionId = session?.id,
           let configSnapshotRepo = configSnapshotRepo {
            let previousBucket = Int(previousPercent / 10)
            let currentBucket = Int(currentPercent / 10)
            if currentBucket > previousBucket {
                Task {
                    let snapshot = ConfigSnapshot(
                        sessionId: sessionId,
                        configType: "budget",
                        version: 0,
                        data: String(format: "%.1f%% used", currentPercent),
                        changedBy: "system",
                        changeReason: "Budget crossed \(currentBucket * 10)% threshold"
                    )
                    try? await configSnapshotRepo.createSnapshot(snapshot)
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

    // MARK: - Auto-Launch: Cockpit → Dashboard → Agent

    /// After chairman assigns slots, auto-configure and launch agents using
    /// Claude Code native orchestration (PRD-S08).
    ///
    /// For each assigned slot:
    /// 1. Generate .claude/agents/ subagent definition
    /// 2. Generate project context (CLAUDE.md + rules) — once for first slot
    /// 3. Generate hooks config (settings.local.json) — once for first slot
    /// 4. Create git worktree (prune + create)
    /// 5. Launch via claude headless mode (stream-json)
    /// 6. Post notifications for dashboard sync
    private func autoLaunchAssignedSlots(_ assignedSlots: [AgentSlot], projectPath: String) async {
        guard let runner = ptyProcessRunner else {
            logger.warning("No PTY runner available — slots created but not auto-launched")
            return
        }

        // Initialize orchestrator if needed
        if orchestrator == nil {
            orchestrator = ClaudeCodeOrchestrator(ptyRunner: runner)
        }

        guard let orchestrator else { return }

        logger.info("Auto-launching \(assignedSlots.count) agents via Claude Code native orchestration...")

        // One-time setup: generate project context and hooks config (first slot only)
        let chairmanBrief = session?.chairmanBrief ?? ""
        var projectContextGenerated = false

        for slot in assignedSlots {
            do {
                // Validate agent type
                guard let agentType = AgentType(rawValue: slot.agentType) else {
                    logger.warning("Unknown agent type: \(slot.agentType) for slot \(slot.slotIndex)")
                    continue
                }

                let adapter = agentType.adapter()
                guard adapter.isAvailable() else {
                    logger.warning("\(agentType.rawValue) CLI not available — skipping slot \(slot.slotIndex)")
                    var errorSlot = slot
                    errorSlot.status = .error
                    let _ = try? await repository.updateSlot(errorSlot)
                    continue
                }

                // --- Step 1: Git worktree setup (keep existing prune + create logic) ---
                let repoURL = URL(fileURLWithPath: projectPath)
                let branchName = slot.branchName ?? "xroads/slot-\(slot.slotIndex)"
                let worktreePath = repoURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("\(repoURL.lastPathComponent)-\(branchName.replacingOccurrences(of: "/", with: "-"))")

                let gitService = GitService()
                let _ = try? await gitService.pruneWorktrees(repoPath: projectPath)
                let _ = try? await gitService.deleteBranch(name: branchName, repoPath: projectPath, force: true)

                do {
                    try await gitService.createWorktree(
                        repoPath: projectPath,
                        branch: branchName,
                        worktreePath: worktreePath.path
                    )
                    logger.info("Worktree created: \(worktreePath.path)")
                } catch {
                    if FileManager.default.fileExists(atPath: worktreePath.path) {
                        logger.info("Reusing existing worktree: \(worktreePath.path)")
                    } else {
                        logger.error("Worktree creation failed: \(error.localizedDescription)")
                        throw error
                    }
                }

                // Update slot to provisioning with worktree path
                var provisioningSlot = slot
                provisioningSlot.status = .provisioning
                provisioningSlot.worktreePath = worktreePath.path
                let _ = try? await repository.updateSlot(provisioningSlot)

                // --- Step 2: One-time project context + hooks generation ---
                if !projectContextGenerated {
                    do {
                        try await orchestrator.generateProjectContext(
                            projectPath: projectPath,
                            cop: cockpitPlan,
                            chairmanBrief: chairmanBrief
                        )
                        try await orchestrator.generateHooksConfig(projectPath: projectPath)
                        projectContextGenerated = true
                        logger.info("Project context and hooks generated for orchestration session")
                    } catch {
                        logger.error("Failed to generate project context: \(error.localizedDescription)")
                        // Non-fatal: continue with launch even without context files
                    }
                }

                // --- Step 3: Generate subagent definition ---
                var slotWithWorktree = provisioningSlot
                slotWithWorktree.worktreePath = worktreePath.path
                slotWithWorktree.branchName = branchName

                let agentDefPath = try await orchestrator.generateAgentDefinition(
                    slot: slotWithWorktree,
                    chairmanBrief: chairmanBrief,
                    projectPath: projectPath
                )
                logger.info("Agent definition generated: \(agentDefPath)")

                // --- Step 4: Inject initial memories (best-effort) ---
                do {
                    // No profiles available yet in most cases — that's fine
                    try await orchestrator.injectInitialMemories(
                        slotIndex: slot.slotIndex,
                        agentType: slot.agentType,
                        projectPath: projectPath,
                        profiles: []
                    )
                } catch {
                    logger.debug("Memory injection skipped: \(error.localizedDescription)")
                }

                // --- Step 5: Launch agent ---
                let slotIndex = slot.slotIndex
                let slotNumber = slotIndex + 1
                let taskDesc = slot.currentTask ?? "Implement assigned stories"
                let projectName = repoURL.lastPathComponent
                let agentName = URL(fileURLWithPath: agentDefPath)
                    .deletingPathExtension().lastPathComponent

                // Determine role from branch name or skill name
                let roleInstructions = Self.roleInstructions(
                    branch: branchName, task: taskDesc, slotNumber: slotNumber
                )

                let prompt = """
                You are Slot \(slotNumber) (\(agentType.displayName)) working on project \(projectName).
                Your role: \(roleInstructions.role)
                Your task: \(taskDesc)
                Your branch: \(branchName)

                Read your agent definition and the project CLAUDE.md for full context.
                Then:
                \(roleInstructions.steps)

                Begin now.
                """

                let sessionIdForSlot = slot.claudeSessionId
                let slotId = slot.id
                let agentTypeRaw = agentType.rawValue

                let outputHandler: @MainActor @Sendable (String) -> Void = { output in
                    NotificationCenter.default.post(
                        name: .cockpitSlotOutput,
                        object: nil,
                        userInfo: [
                            "slotNumber": slotNumber,
                            "output": output,
                            "agentType": agentTypeRaw,
                        ]
                    )
                }

                let terminationHandler: @MainActor @Sendable (Int32) -> Void = { exitCode in
                    NotificationCenter.default.post(
                        name: .cockpitSlotTerminated,
                        object: nil,
                        userInfo: [
                            "slotNumber": slotNumber,
                            "exitCode": exitCode,
                        ]
                    )
                }

                let envVars: [String: String] = [
                    "CROSSROADS_SESSION_ID": self.session?.id.uuidString ?? "",
                    "CROSSROADS_SLOT": String(slotIndex),
                    "CROSSROADS_AGENT": agentTypeRaw,
                    "CROSSROADS_BRANCH": branchName,
                ]

                let headlessSession: HeadlessSession

                if agentType == .claude {
                    // Claude: use headless mode with --agent + stream-json
                    headlessSession = try await orchestrator.launchHeadless(
                        slotIndex: slotIndex,
                        agentName: agentName,
                        prompt: prompt,
                        worktreePath: worktreePath.path,
                        projectPath: projectPath,
                        sessionId: sessionIdForSlot,
                        environment: envVars,
                        onOutput: outputHandler,
                        onTermination: terminationHandler,
                        onSessionId: { [weak self] capturedSessionId in
                            guard let self else { return }
                            Task { @MainActor in
                                if let idx = self.slots.firstIndex(where: { $0.id == slotId }) {
                                    self.slots[idx].claudeSessionId = capturedSessionId
                                }
                                var updatedSlot = slot
                                updatedSlot.claudeSessionId = capturedSessionId
                                let _ = try? await self.repository.updateSlot(updatedSlot)
                            }
                        }
                    )
                } else {
                    // Gemini/Codex: launch native CLI with its own flags
                    headlessSession = try await orchestrator.launchNativeAgent(
                        agentType: agentType,
                        slotIndex: slotIndex,
                        prompt: prompt,
                        worktreePath: worktreePath.path,
                        environment: envVars,
                        onOutput: outputHandler,
                        onTermination: terminationHandler
                    )
                }

                // Update slot to running
                var runningSlot = provisioningSlot
                runningSlot.status = .running
                let _ = try? await repository.updateSlot(runningSlot)

                // Update local state
                if let idx = slots.firstIndex(where: { $0.id == slot.id }) {
                    slots[idx].status = .running
                    slots[idx].worktreePath = worktreePath.path
                }

                slotProcessIds[slot.id] = headlessSession.processId
                logger.info("Slot \(slot.slotIndex) launched via headless mode: \(agentTypeRaw) on \(branchName)")

                // Notify dashboard to sync its TerminalSlot
                NotificationCenter.default.post(
                    name: .cockpitSlotLaunched,
                    object: nil,
                    userInfo: [
                        "slotIndex": slot.slotIndex,
                        "agentType": agentTypeRaw,
                        "branchName": branchName,
                        "processId": headlessSession.processId,
                        "worktreePath": worktreePath.path,
                    ]
                )

                // Small delay between launches to avoid resource contention
                try? await Task.sleep(for: .milliseconds(300))

            } catch {
                logger.error("Failed to auto-launch slot \(slot.slotIndex): \(error.localizedDescription)")
                var errorSlot = slot
                errorSlot.status = .error
                let _ = try? await repository.updateSlot(errorSlot)
            }
        }

        let runningCount = self.slots.filter { $0.status == .running }.count
        logger.info("Auto-launch complete: \(runningCount) agents running")
        // Brain will detect the new slots at its next cycle and report via [CHAT]
    }

    // MARK: - Brain-Initiated Slot Launch

    /// Called when the brain requests a slot launch via [LAUNCH:agent:role:task]
    func launchSlotFromBrain(agentType: String, role: String, task: String, projectPath: String) async {
        guard let session else {
            logger.warning("Cannot launch slot — no active session")
            return
        }

        // Find next available slot index
        let usedIndices = Set(slots.map { $0.slotIndex })
        let nextIndex = (0..<6).first(where: { !usedIndices.contains($0) }) ?? slots.count

        let branchName = "xroads/slot-\(nextIndex + 1)-\(role.lowercased().replacingOccurrences(of: " ", with: "-"))"

        // Create the slot in DB
        var slot = AgentSlot(
            cockpitSessionId: session.id,
            slotIndex: nextIndex,
            status: .empty,
            agentType: agentType,
            branchName: branchName
        )
        slot.currentTask = task

        do {
            let created = try await repository.createSlot(slot)
            slots.append(created)
            logger.info("Brain created slot \(nextIndex): \(agentType) as \(role)")

            // Launch it
            await autoLaunchAssignedSlots([created], projectPath: projectPath)
        } catch {
            logger.error("Failed to create slot from brain request: \(error.localizedDescription)")
        }
    }

    // MARK: - Role-Based Prompting

    /// Maps a slot's branch/task to role-specific instructions.
    /// Roles: implement, review, testing, docs, debug, security, devops
    private static func roleInstructions(branch: String, task: String, slotNumber: Int) -> (role: String, steps: String) {
        let combined = (branch + " " + task).lowercased()

        if combined.contains("test") || combined.contains("qa") || combined.contains("e2e") || combined.contains("perf") {
            return (
                role: "TESTER — Integration, E2E, and performance testing",
                steps: """
                1. Read the codebase to understand what's been implemented
                2. Write integration tests covering cross-module interactions
                3. Write E2E tests for critical user flows
                4. Run all tests and fix any that fail
                5. Commit with prefix [slot-\(slotNumber)]
                """
            )
        }

        if combined.contains("review") || combined.contains("audit") || combined.contains("lint") {
            return (
                role: "REVIEWER — Deep code review and quality analysis",
                steps: """
                1. Read the full codebase systematically
                2. Analyze for: OWASP top 10, SOLID violations, code complexity, dead code
                3. Check for security issues, injection risks, hardcoded secrets
                4. Write a review report at .crossroads/deliverables/code-review.md
                5. Fix critical issues if found, commit with prefix [slot-\(slotNumber)]
                """
            )
        }

        if combined.contains("doc") || combined.contains("readme") || combined.contains("guide") || combined.contains("write") {
            return (
                role: "WRITER — Documentation and technical writing",
                steps: """
                1. Read the codebase to understand architecture and APIs
                2. Generate/update README.md with accurate setup, usage, and architecture docs
                3. Generate API documentation for public interfaces
                4. Write developer guides for key workflows
                5. Commit with prefix [slot-\(slotNumber)]
                """
            )
        }

        if combined.contains("security") || combined.contains("compliance") {
            return (
                role: "SECURITY AUDITOR — Vulnerability assessment and compliance",
                steps: """
                1. Scan the codebase for security vulnerabilities
                2. Check auth flows, input validation, data exposure
                3. Review dependency versions for known CVEs
                4. Write security audit report at .crossroads/deliverables/security-audit.md
                5. Fix critical vulnerabilities, commit with prefix [slot-\(slotNumber)]
                """
            )
        }

        if combined.contains("debug") || combined.contains("fix") || combined.contains("bug") {
            return (
                role: "DEBUGGER — Bug reproduction, diagnosis, and fix",
                steps: """
                1. Reproduce the reported issue
                2. Diagnose the root cause (not just the symptom)
                3. Implement the fix with minimal blast radius
                4. Write regression tests
                5. Commit with prefix [slot-\(slotNumber)]
                """
            )
        }

        if combined.contains("devops") || combined.contains("deploy") || combined.contains("ci") || combined.contains("infra") {
            return (
                role: "DEVOPS — Infrastructure, CI/CD, and deployment",
                steps: """
                1. Analyze current infrastructure and deployment setup
                2. Implement the assigned infrastructure task
                3. Test the pipeline/deployment locally
                4. Document changes in deployment guide
                5. Commit with prefix [slot-\(slotNumber)]
                """
            )
        }

        // Default: implementer
        return (
            role: "IMPLEMENTER — Feature development and unit testing",
            steps: """
            1. Understand the codebase structure
            2. Implement your assigned task
            3. Write unit tests with good coverage
            4. Commit with prefix [slot-\(slotNumber)]
            """
        )
    }

    // MARK: - Intelligence Wiring: Slot Termination

    /// WIRING 1+2: Records a learning record and auto-extracts memories when a slot terminates.
    /// Called from AppState.handleSlotTermination via the cockpit view model reference.
    func recordSlotCompletion(slotNumber: Int, exitCode: Int32) {
        guard let sessionId = session?.id,
              let learningRepo = learningRepo else { return }

        // Find the slot by 1-based slotNumber
        let slotIndex = slotNumber - 1
        guard let slot = slots.first(where: { $0.slotIndex == slotIndex }) else { return }

        // Notify chat about slot completion
        let status = exitCode == 0 ? "completed" : "failed (code \(exitCode))"
        let task = slot.currentTask ?? "unknown task"
        NotificationCenter.default.post(
            name: .cockpitBrainToChat,
            object: nil,
            userInfo: ["content": "Slot \(slotNumber) (\(slot.agentType)) \(status): \(task)"]
        )

        let slotCost = slotCosts[slot.id]?.totalCostCents ?? 0
        // Estimate elapsed time: use createdAt delta or a default
        let elapsed = Int(Date().timeIntervalSince(slot.createdAt) * 1000)

        Task {
            // WIRING 1: Record learning data
            let record = LearningRecord(
                sessionId: sessionId,
                storyId: "slot-\(slotNumber)",
                storyTitle: slot.currentTask ?? "unknown",
                storyComplexity: "moderate",
                agentType: slot.agentType,
                durationMs: elapsed,
                costCents: slotCost,
                filesChanged: 0, linesAdded: 0, linesRemoved: 0,
                testsRun: 0, testsPassed: 0, testsFailed: 0,
                conflictsEncountered: 0, retriesNeeded: 0,
                success: exitCode == 0,
                failureReason: exitCode != 0 ? "exit code \(exitCode)" : nil,
                filePatterns: "[]"
            )
            let _ = try? await learningRepo.recordLearning(record)

            // Update performance profile
            let domain = Self.categorizeDomain(from: slot.currentTask ?? "")
            try? await learningRepo.updatePerformanceProfile(
                agentType: slot.agentType, taskCategory: domain, from: record
            )

            logger.info("Recorded learning for slot \(slotNumber): success=\(exitCode == 0), cost=\(slotCost)¢, elapsed=\(elapsed)ms")

            // WIRING 2: Auto-extract memories from session records
            if let agentMemoryRepo = agentMemoryRepo {
                let records = (try? await learningRepo.fetchRecords(sessionId: sessionId)) ?? []
                let _ = try? await agentMemoryRepo.autoExtractMemories(
                    sessionId: sessionId, records: records
                )
            }
        }
    }

    // MARK: - Private: Domain Categorization Helper

    /// Simple domain categorization from task title for trust score computation.
    static func categorizeDomain(from title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("rust") || lower.contains("backend") || lower.contains("api") { return "backend_rust" }
        if lower.contains("react") || lower.contains("frontend") || lower.contains("ui") { return "frontend_react" }
        if lower.contains("swift") || lower.contains("ios") || lower.contains("macos") { return "ios_swift" }
        if lower.contains("test") { return "testing" }
        if lower.contains("sql") || lower.contains("migration") || lower.contains("database") { return "db_migration" }
        if lower.contains("deploy") || lower.contains("ci") || lower.contains("docker") { return "devops" }
        if lower.contains("doc") || lower.contains("readme") { return "docs" }
        return "general"
    }
}
