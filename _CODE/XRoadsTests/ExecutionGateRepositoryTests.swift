import XCTest
import GRDB
@testable import XRoadsLib

/// US-001: Validates ExecutionGate SQLite persistence and lifecycle transitions
final class ExecutionGateRepositoryTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var sessionRepo: CockpitSessionRepository!
    private var gateRepo: ExecutionGateRepository!
    private var testSlotId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        dbManager = try CockpitDatabaseManager()
        let dbQueue = await dbManager.dbQueue
        sessionRepo = CockpitSessionRepository(dbQueue: dbQueue)
        gateRepo = ExecutionGateRepository(dbQueue: dbQueue)

        // Create a session + slot for FK reference
        let session = try await sessionRepo.createSession(
            CockpitSession(projectPath: "/tmp/gate-test", status: .active)
        )
        let slot = try await sessionRepo.createSlot(
            AgentSlot(
                cockpitSessionId: session.id,
                slotIndex: 0,
                agentType: "claude"
            )
        )
        testSlotId = slot.id
    }

    override func tearDown() async throws {
        gateRepo = nil
        sessionRepo = nil
        dbManager = nil
        testSlotId = nil
        try await super.tearDown()
    }

    // MARK: - Assertion 1: should create ExecutionGate with FK to AgentSlot

    func test_createGate_persistsWithFKToAgentSlot() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "git_push",
            operationPayload: "git push origin main --force",
            riskLevel: "critical",
            estimatedImpact: "Force push overwrites remote history"
        )

        XCTAssertEqual(gate.agentSlotId, testSlotId)
        XCTAssertEqual(gate.status, .pending)
        XCTAssertEqual(gate.operationType, "git_push")
        XCTAssertEqual(gate.riskLevel, "critical")

        // Verify it can be fetched back
        let fetched = try await gateRepo.fetch(id: gate.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.agentSlotId, testSlotId)
    }

    func test_createGate_FKEnforced_invalidSlotFails() async throws {
        let bogusSlotId = UUID()
        do {
            _ = try await gateRepo.create(
                agentSlotId: bogusSlotId,
                operationType: "rm_rf",
                operationPayload: "rm -rf /",
                riskLevel: "critical"
            )
            XCTFail("Should have thrown due to FK constraint violation")
        } catch {
            // Expected: GRDB throws a DatabaseError for FK violation
            XCTAssertTrue(error is DatabaseError, "Expected DatabaseError, got: \(error)")
        }
    }

    func test_cascadeDelete_removesGatesWhenSlotDeleted() async throws {
        _ = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "npm_install",
            operationPayload: "npm install malicious-pkg",
            riskLevel: "high"
        )

        let gatesBefore = try await gateRepo.fetchGates(slotId: testSlotId)
        XCTAssertEqual(gatesBefore.count, 1)

        // Delete the slot — gate should cascade
        try await sessionRepo.deleteSlot(id: testSlotId)

        let gatesAfter = try await gateRepo.fetchGates(slotId: testSlotId)
        XCTAssertEqual(gatesAfter.count, 0)
    }

    // MARK: - Assertion 2: should transition through lifecycle states correctly

    func test_lifecycle_pendingToDryRun_viaPolicyAllow() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "file_delete",
            operationPayload: "rm important.swift",
            riskLevel: "high"
        )

        let updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyAllow,
            context: ExecutionGateGuardContext(requiresDryRun: true)
        )

        XCTAssertEqual(updated.status, .dryRun)
    }

    func test_lifecycle_pendingToRejected_viaPolicyDeny() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "drop_table",
            operationPayload: "DROP TABLE users",
            riskLevel: "critical"
        )

        let updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDeny,
            deniedReason: "Operation too dangerous"
        )

        XCTAssertEqual(updated.status, .rejected)
        XCTAssertEqual(updated.deniedReason, "Operation too dangerous")
    }

    func test_lifecycle_pendingToExecuting_viaPolicyDirect() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "cat_file",
            operationPayload: "cat README.md",
            riskLevel: "low"
        )

        let updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDirect,
            context: ExecutionGateGuardContext(riskIsLow: true)
        )

        XCTAssertEqual(updated.status, .executing)
    }

    func test_lifecycle_fullApprovalFlow() async throws {
        // pending -> dry_run -> awaiting_approval -> executing -> completed
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "git_rebase",
            operationPayload: "git rebase -i HEAD~5",
            riskLevel: "high"
        )

        // pending -> dry_run
        var updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyAllow,
            context: ExecutionGateGuardContext(requiresDryRun: true)
        )
        XCTAssertEqual(updated.status, .dryRun)

        // dry_run -> awaiting_approval
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .dryRunDone,
            context: ExecutionGateGuardContext(dryRunFeasible: true)
        )
        XCTAssertEqual(updated.status, .awaitingApproval)

        // awaiting_approval -> executing
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .approve,
            context: ExecutionGateGuardContext(approvedByHuman: true),
            approvedBy: "user@xroads"
        )
        XCTAssertEqual(updated.status, .executing)
        XCTAssertEqual(updated.approvedBy, "user@xroads")
        XCTAssertNotNil(updated.approvedAt)

        // executing -> completed
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .success
        )
        XCTAssertEqual(updated.status, .completed)
    }

    func test_lifecycle_executingToRolledBack_onAnomaly() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "deploy",
            operationPayload: "kubectl apply -f deploy.yaml",
            riskLevel: "high"
        )

        // pending -> executing (direct, low risk)
        var updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDirect,
            context: ExecutionGateGuardContext(riskIsLow: true)
        )

        // executing -> rolled_back
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .anomaly
        )
        XCTAssertEqual(updated.status, .rolledBack)
    }

    // MARK: - Assertion 3: should write immutable audit_entry on completion

    func test_writeAudit_onCompleted() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "file_write",
            operationPayload: "echo hello > file.txt",
            riskLevel: "low"
        )

        // Move to completed
        var updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDirect,
            context: ExecutionGateGuardContext(riskIsLow: true)
        )
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .success
        )
        XCTAssertEqual(updated.status, .completed)

        // Write audit
        let audited = try await gateRepo.writeAudit(gateId: updated.id, durationMs: 150)
        XCTAssertNotNil(audited.auditEntry)

        // Parse audit entry JSON
        let data = audited.auditEntry!.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(AuditEntry.self, from: data)
        XCTAssertEqual(entry.gateId, gate.id)
        XCTAssertEqual(entry.finalStatus, "completed")
        XCTAssertEqual(entry.operationType, "file_write")
        XCTAssertEqual(entry.durationMs, 150)
    }

    func test_writeAudit_onRolledBack() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "db_migration",
            operationPayload: "migrate --apply",
            riskLevel: "high"
        )

        var updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDirect,
            context: ExecutionGateGuardContext(riskIsLow: true)
        )
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .anomaly
        )

        let audited = try await gateRepo.writeAudit(gateId: updated.id)
        XCTAssertNotNil(audited.auditEntry)

        let data = audited.auditEntry!.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(AuditEntry.self, from: data)
        XCTAssertEqual(entry.finalStatus, "rolled_back")
    }

    func test_writeAudit_immutable_cannotWriteTwice() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "file_write",
            operationPayload: "echo test",
            riskLevel: "low"
        )

        var updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDirect,
            context: ExecutionGateGuardContext(riskIsLow: true)
        )
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .success
        )

        // First write succeeds
        _ = try await gateRepo.writeAudit(gateId: updated.id)

        // Second write must fail (immutability)
        do {
            _ = try await gateRepo.writeAudit(gateId: updated.id)
            XCTFail("Should have thrown auditAlreadyWritten")
        } catch let error as ExecutionGateRepositoryError {
            if case .auditAlreadyWritten(let id) = error {
                XCTAssertEqual(id, updated.id)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_writeAudit_rejectsNonTerminalState() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "test",
            operationPayload: "test",
            riskLevel: "low"
        )

        // Gate is in pending state — not terminal
        do {
            _ = try await gateRepo.writeAudit(gateId: gate.id)
            XCTFail("Should have thrown lifecycleViolation")
        } catch let error as ExecutionGateRepositoryError {
            if case .lifecycleViolation = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Assertion 4: should reject direct status override bypassing lifecycle

    func test_directStatusOverride_rejected() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "test",
            operationPayload: "test",
            riskLevel: "low"
        )

        // Try invalid transition: pending -> completed (skipping lifecycle)
        do {
            _ = try await gateRepo.updateStatus(
                gateId: gate.id,
                event: .success
            )
            XCTFail("Should have thrown invalidTransition")
        } catch let error as ExecutionGateStateMachineError {
            if case .invalidTransition(let from, let event) = error {
                XCTAssertEqual(from, .pending)
                XCTAssertEqual(event, .success)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_guardViolation_policyDirectWithoutLowRisk() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "test",
            operationPayload: "test",
            riskLevel: "high"
        )

        // policy_direct requires risk_is_low guard
        do {
            _ = try await gateRepo.updateStatus(
                gateId: gate.id,
                event: .policyDirect,
                context: ExecutionGateGuardContext(riskIsLow: false)
            )
            XCTFail("Should have thrown guardViolation")
        } catch let error as ExecutionGateStateMachineError {
            if case .guardViolation(let guardName, _) = error {
                XCTAssertEqual(guardName, "risk_is_low")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_guardViolation_approveWithoutHuman() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "test",
            operationPayload: "test",
            riskLevel: "high"
        )

        // Move to awaiting_approval
        var updated = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyAllow,
            context: ExecutionGateGuardContext(requiresDryRun: true)
        )
        updated = try await gateRepo.updateStatus(
            gateId: updated.id,
            event: .dryRunDone,
            context: ExecutionGateGuardContext(dryRunFeasible: true)
        )
        XCTAssertEqual(updated.status, .awaitingApproval)

        // approve without approvedByHuman guard
        do {
            _ = try await gateRepo.updateStatus(
                gateId: updated.id,
                event: .approve,
                context: ExecutionGateGuardContext(approvedByHuman: false)
            )
            XCTFail("Should have thrown guardViolation")
        } catch let error as ExecutionGateStateMachineError {
            if case .guardViolation(let guardName, _) = error {
                XCTAssertEqual(guardName, "approved_by_human")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_terminalState_rejectsFurtherTransitions() async throws {
        let gate = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "test",
            operationPayload: "test",
            riskLevel: "low"
        )

        // Move to rejected (terminal)
        let rejected = try await gateRepo.updateStatus(
            gateId: gate.id,
            event: .policyDeny
        )
        XCTAssertEqual(rejected.status, .rejected)

        // Any further event from terminal state should fail
        do {
            _ = try await gateRepo.updateStatus(
                gateId: rejected.id,
                event: .policyAllow,
                context: ExecutionGateGuardContext(requiresDryRun: true)
            )
            XCTFail("Should have thrown invalidTransition from terminal state")
        } catch let error as ExecutionGateStateMachineError {
            if case .invalidTransition(let from, _) = error {
                XCTAssertEqual(from, .rejected)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Fetch Gates by Slot

    func test_fetchGatesBySlot() async throws {
        _ = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "op1",
            operationPayload: "payload1",
            riskLevel: "low"
        )
        _ = try await gateRepo.create(
            agentSlotId: testSlotId,
            operationType: "op2",
            operationPayload: "payload2",
            riskLevel: "high"
        )

        let gates = try await gateRepo.fetchGates(slotId: testSlotId)
        XCTAssertEqual(gates.count, 2)
    }
}
