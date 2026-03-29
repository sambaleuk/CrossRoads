import Foundation
import GRDB
import os

// MARK: - SafeExecPayload

/// Structured payload emitted by agents via [SAFEEXEC:{...}] protocol.
/// Agents emit lines like: [SAFEEXEC:{"op_type":"git_push","raw_intent":"git push origin main --force","risk_level":"critical"}]
struct SafeExecPayload: Codable, Sendable, Equatable {
    let opType: String
    let rawIntent: String
    let riskLevel: String

    enum CodingKeys: String, CodingKey {
        case opType = "op_type"
        case rawIntent = "raw_intent"
        case riskLevel = "risk_level"
    }
}

// MARK: - SafeExecOutputParser

/// Parses PTY stdout lines for [SAFEEXEC:{...}] messages.
/// Uses Swift Codable JSON decoding — no regex.
struct SafeExecOutputParser: Sendable {

    private static let prefix = "[SAFEEXEC:"
    private static let suffix: Character = "]"

    /// Attempt to extract a SafeExecPayload from a stdout line.
    /// Returns nil if the line does not contain a valid [SAFEEXEC:{...}] message.
    func parse(line: String) -> SafeExecPayload? {
        guard let prefixRange = line.range(of: Self.prefix) else {
            return nil
        }

        let afterPrefix = line[prefixRange.upperBound...]
        guard let closingIndex = afterPrefix.lastIndex(of: Self.suffix) else {
            return nil
        }

        let jsonString = String(afterPrefix[afterPrefix.startIndex..<closingIndex])

        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(SafeExecPayload.self, from: data)
    }

    /// Scan a chunk of stdout text (may contain multiple lines) for all SAFEEXEC payloads.
    func parseAll(text: String) -> [SafeExecPayload] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parse(line: String($0)) }
    }
}

// MARK: - SafeExecutorInterceptorError

enum SafeExecutorInterceptorError: LocalizedError {
    case slotNotFound(UUID)
    case slotNotRunning(UUID, AgentSlotStatus)
    case suspendFailed(pid: pid_t, reason: String)

    var errorDescription: String? {
        switch self {
        case .slotNotFound(let id):
            return "AgentSlot not found: \(id)"
        case .slotNotRunning(let id, let status):
            return "AgentSlot \(id) is not running (current: \(status.rawValue))"
        case .suspendFailed(let pid, let reason):
            return "Failed to suspend process pid=\(pid): \(reason)"
        }
    }
}

// MARK: - SafeExecutorInterceptor

/// Intercepts [SAFEEXEC:{...}] lines from agent stdout, creates ExecutionGate records,
/// suspends the agent process, and transitions the AgentSlot to waiting_approval.
///
/// Wired into the PTY output pipeline alongside SlotMessagePublisher.
actor SafeExecutorInterceptor {

    private let logger = Logger(subsystem: "com.xroads", category: "SafeExecInterceptor")
    private let parser = SafeExecOutputParser()
    private let gateRepo: ExecutionGateRepository
    private let dbQueue: DatabaseQueue
    private let ptyRunner: PTYProcessRunner
    /// Phase 5: Org chart service for gate approval routing (optional for backward compat)
    private let orgChartService: OrgChartService?
    /// Session ID for org chart lookups
    private var sessionId: UUID?

    init(
        gateRepo: ExecutionGateRepository,
        dbQueue: DatabaseQueue,
        ptyRunner: PTYProcessRunner,
        orgChartService: OrgChartService? = nil,
        sessionId: UUID? = nil
    ) {
        self.gateRepo = gateRepo
        self.dbQueue = dbQueue
        self.ptyRunner = ptyRunner
        self.orgChartService = orgChartService
        self.sessionId = sessionId
    }

    // MARK: - Public

    /// Process a chunk of PTY stdout text for a given slot and its PTY process ID.
    /// If a [SAFEEXEC:{...}] line is detected:
    /// 1. Create an ExecutionGate in pending state
    /// 2. Suspend the agent process via SIGSTOP
    /// 3. Transition the AgentSlot from running to waiting_approval
    ///
    /// Returns the created ExecutionGate if interception occurred, nil otherwise.
    @discardableResult
    func processOutput(text: String, slotId: UUID, processId: UUID) async -> ExecutionGate? {
        let payloads = parser.parseAll(text: text)
        guard let payload = payloads.first else { return nil }

        // Only intercept the first SAFEEXEC per chunk — one gate at a time
        do {
            return try await intercept(payload: payload, slotId: slotId, processId: processId)
        } catch {
            let errorDesc = error.localizedDescription
            logger.error("SafeExec interception failed: \(errorDesc)")
            return nil
        }
    }

    // MARK: - Private

    private func intercept(
        payload: SafeExecPayload,
        slotId: UUID,
        processId: UUID
    ) async throws -> ExecutionGate {
        // 1. Verify slot is in running state
        let slot = try fetchSlot(id: slotId)
        guard slot.status == .running else {
            throw SafeExecutorInterceptorError.slotNotRunning(slotId, slot.status)
        }

        logger.info("SafeExec intercepted: op=\(payload.opType) risk=\(payload.riskLevel) slot=\(slotId)")

        // 2. Create ExecutionGate record
        let gate = try await gateRepo.create(
            agentSlotId: slotId,
            operationType: payload.opType,
            operationPayload: payload.rawIntent,
            riskLevel: payload.riskLevel
        )

        // WIRING 6: Route gate approval through org chart hierarchy
        if let orgChartService = orgChartService, let sessionId = sessionId {
            Task {
                do {
                    let approverId = try await orgChartService.routeGateApproval(
                        sessionId: sessionId,
                        slotId: slotId,
                        riskLevel: payload.riskLevel
                    )
                    logger.info("Gate \(gate.id) routed to approver role \(approverId) based on risk=\(payload.riskLevel)")
                } catch {
                    logger.warning("Gate approval routing failed (falling back to human): \(error.localizedDescription)")
                }
            }
        }

        // 3. Suspend agent process via SIGSTOP
        try await suspendProcess(processId: processId)

        // 4. Transition AgentSlot from running -> waiting_approval
        try transitionSlotToWaitingApproval(slotId: slotId)

        logger.info("Agent suspended, slot \(slotId) now waiting_approval, gate=\(gate.id)")

        return gate
    }

    private func suspendProcess(processId: UUID) async throws {
        guard let info = await ptyRunner.getProcessInfo(id: processId) else {
            logger.warning("Process \(processId) not found for suspension — may be in test mode")
            return
        }

        let pid = info.pid
        guard pid > 0 else {
            logger.warning("Process \(processId) has invalid pid \(pid) — skipping SIGSTOP")
            return
        }

        let result = kill(pid, SIGSTOP)
        if result != 0 {
            let errnoValue = errno
            throw SafeExecutorInterceptorError.suspendFailed(
                pid: pid,
                reason: String(cString: strerror(errnoValue))
            )
        }

        logger.info("SIGSTOP sent to pid \(pid)")
    }

    private func fetchSlot(id: UUID) throws -> AgentSlot {
        try dbQueue.read { db in
            guard let slot = try AgentSlot.fetchOne(db, key: id) else {
                throw SafeExecutorInterceptorError.slotNotFound(id)
            }
            return slot
        }
    }

    private func transitionSlotToWaitingApproval(slotId: UUID) throws {
        try dbQueue.write { db in
            guard var slot = try AgentSlot.fetchOne(db, key: slotId) else {
                throw SafeExecutorInterceptorError.slotNotFound(slotId)
            }
            slot.status = .waitingApproval
            slot.updatedAt = Date()
            try slot.update(db)
        }
    }
}
