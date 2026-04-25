import XCTest
import GRDB
@testable import XRoadsLib

/// US-002: Validates stdout interception, gate creation, and agent suspension
final class SafeExecutorInterceptorTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var sessionRepo: CockpitSessionRepository!
    private var gateRepo: ExecutionGateRepository!
    private var ptyRunner: PTYProcessRunner!
    private var interceptor: SafeExecutorInterceptor!

    // Shared test fixtures
    private var session: CockpitSession!
    private var slot: AgentSlot!

    override func setUp() async throws {
        try await super.setUp()
        dbManager = try CockpitDatabaseManager()
        let dbQueue = await dbManager.dbQueue
        sessionRepo = CockpitSessionRepository(dbQueue: dbQueue)
        gateRepo = ExecutionGateRepository(dbQueue: dbQueue)
        ptyRunner = PTYProcessRunner(testMode: true)
        interceptor = SafeExecutorInterceptor(
            gateRepo: gateRepo,
            dbQueue: dbQueue,
            ptyRunner: ptyRunner
        )

        session = try await sessionRepo.createSession(
            CockpitSession(projectPath: "/tmp/safeexec-test", status: .active)
        )
        slot = try await sessionRepo.createSlot(
            AgentSlot(
                cockpitSessionId: session.id,
                slotIndex: 0,
                status: .running,
                agentType: "claude"
            )
        )
    }

    override func tearDown() async throws {
        interceptor = nil
        ptyRunner = nil
        gateRepo = nil
        sessionRepo = nil
        dbManager = nil
        session = nil
        slot = nil
        try await super.tearDown()
    }

    // MARK: - Assertion 1: should detect [SAFEEXEC:] prefix in agent stdout

    func test_parser_detectsSafeExecPrefix() {
        let parser = SafeExecOutputParser()
        let line = """
        Some output [SAFEEXEC:{"op_type":"git_push","raw_intent":"git push origin main --force","risk_level":"critical"}] more
        """
        let payload = parser.parse(line: line)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.opType, "git_push")
        XCTAssertEqual(payload?.rawIntent, "git push origin main --force")
        XCTAssertEqual(payload?.riskLevel, "critical")
    }

    func test_parser_returnsNilForNonSafeExecLine() {
        let parser = SafeExecOutputParser()
        let line = "Regular stdout output without SAFEEXEC markers"
        let payload = parser.parse(line: line)
        XCTAssertNil(payload)
    }

    func test_parser_returnsNilForMalformedJSON() {
        let parser = SafeExecOutputParser()
        let line = "[SAFEEXEC:not valid json]"
        let payload = parser.parse(line: line)
        XCTAssertNil(payload)
    }

    func test_parser_parseAllExtractsMultiplePayloads() {
        let parser = SafeExecOutputParser()
        let text = """
        Regular output
        [SAFEEXEC:{"op_type":"git_push","raw_intent":"git push","risk_level":"high"}]
        More output
        [SAFEEXEC:{"op_type":"rm_rf","raw_intent":"rm -rf /tmp","risk_level":"critical"}]
        """
        let payloads = parser.parseAll(text: text)
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0].opType, "git_push")
        XCTAssertEqual(payloads[1].opType, "rm_rf")
    }

    func test_parser_ignoresXROADSPrefix() {
        let parser = SafeExecOutputParser()
        let line = "[XROADS:{\"type\":\"status\",\"content\":\"Working\"}]"
        let payload = parser.parse(line: line)
        XCTAssertNil(payload)
    }

    // MARK: - Assertion 2: should create ExecutionGate from parsed intent

    func test_interceptor_createsExecutionGateFromParsedIntent() async throws {
        let stdout = "[SAFEEXEC:{\"op_type\":\"git_push\",\"raw_intent\":\"git push origin main --force\",\"risk_level\":\"critical\"}]\n"

        let gate = await interceptor.processOutput(
            text: stdout,
            slotId: slot.id,
            processId: UUID()
        )

        XCTAssertNotNil(gate)
        XCTAssertEqual(gate?.agentSlotId, slot.id)
        XCTAssertEqual(gate?.operationType, "git_push")
        XCTAssertEqual(gate?.operationPayload, "git push origin main --force")
        XCTAssertEqual(gate?.riskLevel, "critical")
        XCTAssertEqual(gate?.status, .pending)

        // Verify persisted in DB
        let fetched = try await gateRepo.fetch(id: gate!.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.operationType, "git_push")
    }

    func test_interceptor_returnsNilForNonSafeExecOutput() async throws {
        let stdout = "Regular output with no SAFEEXEC markers\n"

        let gate = await interceptor.processOutput(
            text: stdout,
            slotId: slot.id,
            processId: UUID()
        )

        XCTAssertNil(gate)

        // No gates created
        let gates = try await gateRepo.fetchGates(slotId: slot.id)
        XCTAssertEqual(gates.count, 0)
    }

    // MARK: - Assertion 3: should suspend agent process on gate creation

    func test_interceptor_processOutputCallsSuspend() async throws {
        // In testMode, PTYProcessRunner returns mock UUIDs and getProcessInfo returns nil
        // so SIGSTOP is skipped (logged as warning). We verify no crash and gate is still created.
        let stdout = "[SAFEEXEC:{\"op_type\":\"npm_install\",\"raw_intent\":\"npm install evil-pkg\",\"risk_level\":\"high\"}]\n"

        let gate = await interceptor.processOutput(
            text: stdout,
            slotId: slot.id,
            processId: UUID()
        )

        // Gate created even when process info unavailable (test mode)
        XCTAssertNotNil(gate)
        XCTAssertEqual(gate?.operationType, "npm_install")
    }

    // MARK: - Assertion 4: should transition AgentSlot to waiting_approval

    func test_interceptor_transitionsSlotToWaitingApproval() async throws {
        let stdout = "[SAFEEXEC:{\"op_type\":\"file_delete\",\"raw_intent\":\"rm important.swift\",\"risk_level\":\"high\"}]\n"

        // Slot starts as running
        let slotBefore = try await sessionRepo.fetchSlot(id: slot.id)
        XCTAssertEqual(slotBefore?.status, .running)

        _ = await interceptor.processOutput(
            text: stdout,
            slotId: slot.id,
            processId: UUID()
        )

        // Slot is now waiting_approval
        let slotAfter = try await sessionRepo.fetchSlot(id: slot.id)
        XCTAssertEqual(slotAfter?.status, .waitingApproval)
    }

    func test_interceptor_rejectsNonRunningSlot() async throws {
        // Set slot to paused
        var pausedSlot = slot!
        pausedSlot.status = .paused
        _ = try await sessionRepo.updateSlot(pausedSlot)

        let stdout = "[SAFEEXEC:{\"op_type\":\"test\",\"raw_intent\":\"test\",\"risk_level\":\"low\"}]\n"

        let gate = await interceptor.processOutput(
            text: stdout,
            slotId: slot.id,
            processId: UUID()
        )

        // Interception should fail silently (logged error)
        XCTAssertNil(gate)

        // No gates created
        let gates = try await gateRepo.fetchGates(slotId: slot.id)
        XCTAssertEqual(gates.count, 0)
    }

    // MARK: - State transition test from preflight

    func test_agentSlotLifecycle_runningToWaitingApproval_onGateTriggered() async throws {
        // This test validates the state machine transition specified in states.json:
        // AgentSlotLifecycle: running -> gate_triggered -> waiting_approval
        let stdout = "[SAFEEXEC:{\"op_type\":\"deploy\",\"raw_intent\":\"kubectl apply\",\"risk_level\":\"critical\"}]\n"

        // Pre-condition: slot is running
        XCTAssertEqual(slot.status, .running)

        let gate = await interceptor.processOutput(
            text: stdout,
            slotId: slot.id,
            processId: UUID()
        )

        // Post-condition: gate created in pending, slot in waiting_approval
        XCTAssertNotNil(gate)
        XCTAssertEqual(gate?.status, .pending)

        let updatedSlot = try await sessionRepo.fetchSlot(id: slot.id)
        XCTAssertEqual(updatedSlot?.status, .waitingApproval)
    }
}
