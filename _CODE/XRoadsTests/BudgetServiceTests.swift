import XCTest
import GRDB
@testable import XRoadsLib

/// Unit tests for `BudgetService`.
///
/// Covers PRD-S02 / US-002, US-003, US-004 acceptance criteria:
///   - checkBudget transitions ok → warning → exceeded
///   - getProjection computes burn rate and time-to-exhaustion
///   - applyThrottle / autoThrottle round-trip with alert audit
///   - routeModel pressure scaling under different budget loads
final class BudgetServiceTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var sessionRepo: CockpitSessionRepository!
    private var costRepo: CostEventRepository!
    private var budgetRepo: BudgetRepository!
    private var service: BudgetService!

    override func setUp() async throws {
        dbManager = try CockpitDatabaseManager() // in-memory
        let dbQueue = await dbManager.dbQueue
        sessionRepo = CockpitSessionRepository(dbQueue: dbQueue)
        costRepo = CostEventRepository(dbQueue: dbQueue)
        budgetRepo = BudgetRepository(dbQueue: dbQueue)
        service = BudgetService(budgetRepository: budgetRepo, costEventRepository: costRepo)
    }

    // MARK: - Helpers

    /// Creates session + slot + slot-level BudgetConfig with a default 1000¢ cap.
    private func makeFixture(
        budgetCents: Int = 1000,
        warningThresholdPct: Int = 80
    ) async throws -> (CockpitSession, AgentSlot, BudgetConfig) {
        let session = try await sessionRepo.createSession(
            CockpitSession(projectPath: "/tmp/budget-svc-\(UUID().uuidString)")
        )
        let slot = try await sessionRepo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: 0, agentType: "claude")
        )
        let cfg = try await budgetRepo.createConfig(
            BudgetConfig(
                sessionId: session.id,
                slotId: slot.id,
                budgetCents: budgetCents,
                warningThresholdPct: warningThresholdPct
            )
        )
        return (session, slot, cfg)
    }

    /// Inserts an explicit-cost CostEvent so we don't depend on pricing tables.
    private func recordSpend(slotId: UUID, cents: Int, at: Date = Date()) async throws {
        let event = CostEvent(
            agentSlotId: slotId,
            provider: "test",
            model: "test-model",
            inputTokens: 0,
            outputTokens: 0,
            costCents: cents,
            createdAt: at
        )
        _ = try await costRepo.record(event)
    }

    // MARK: - checkBudget

    func test_checkBudget_throwsWhenNoConfig() async throws {
        let session = try await sessionRepo.createSession(
            CockpitSession(projectPath: "/tmp/budget-svc-noconfig")
        )
        let slot = try await sessionRepo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: 0, agentType: "claude")
        )

        do {
            _ = try await service.checkBudget(slotId: slot.id)
            XCTFail("Expected checkBudget to throw configNotFound")
        } catch let error as BudgetServiceError {
            switch error {
            case .configNotFound:
                break // expected
            default:
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func test_checkBudget_okWhenSpendBelowWarning() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000, warningThresholdPct: 80)
        try await recordSpend(slotId: slot.id, cents: 200) // 20%

        let status = try await service.checkBudget(slotId: slot.id)

        XCTAssertEqual(status.status, "ok")
        XCTAssertEqual(status.percentUsed, 20.0, accuracy: 0.001)
        XCTAssertEqual(status.remainingCents, 800)
    }

    func test_checkBudget_warningAtThreshold() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000, warningThresholdPct: 80)
        try await recordSpend(slotId: slot.id, cents: 850) // 85%

        let status = try await service.checkBudget(slotId: slot.id)

        XCTAssertEqual(status.status, "warning")
        XCTAssertEqual(status.percentUsed, 85.0, accuracy: 0.001)
    }

    func test_checkBudget_exceededAtOrAbove100() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000)
        try await recordSpend(slotId: slot.id, cents: 1200) // 120%

        let status = try await service.checkBudget(slotId: slot.id)

        XCTAssertEqual(status.status, "exceeded")
        XCTAssertGreaterThanOrEqual(status.percentUsed, 100.0)
        XCTAssertEqual(status.remainingCents, -200, "remainingCents may go negative when exceeded")
    }

    // MARK: - getProjection

    func test_getProjection_returnsZeroBurnRateForSingleEvent() async throws {
        let (session, slot, _) = try await makeFixture(budgetCents: 1000)
        // Need a session-level config too — getProjection looks for slotId == nil
        _ = try await budgetRepo.createConfig(
            BudgetConfig(sessionId: session.id, slotId: nil, budgetCents: 5000)
        )
        try await recordSpend(slotId: slot.id, cents: 100)

        let projection = try await service.getProjection(sessionId: session.id)

        // Single event = no time span = burn rate 0
        XCTAssertEqual(projection.burnRateCentsPerHour, 0.0)
        XCTAssertEqual(projection.currentSpend, 100)
        XCTAssertFalse(projection.overBudget)
    }

    func test_getProjection_computesBurnRateAcrossEvents() async throws {
        let (session, slot, _) = try await makeFixture(budgetCents: 1000)
        _ = try await budgetRepo.createConfig(
            BudgetConfig(sessionId: session.id, slotId: nil, budgetCents: 5000)
        )

        // 200¢ over 2 hours = 100¢/hour
        let now = Date()
        try await recordSpend(slotId: slot.id, cents: 100, at: now.addingTimeInterval(-7200))
        try await recordSpend(slotId: slot.id, cents: 100, at: now)

        let projection = try await service.getProjection(sessionId: session.id)

        XCTAssertEqual(projection.currentSpend, 200)
        XCTAssertEqual(projection.burnRateCentsPerHour, 100.0, accuracy: 0.5)
        XCTAssertNotNil(projection.timeToExhaustionMinutes)
    }

    func test_getProjection_flagsOverBudgetWhenProjectedExceedsCap() async throws {
        let (session, slot, _) = try await makeFixture(budgetCents: 100)
        // Session-level cap deliberately tight: 200¢
        _ = try await budgetRepo.createConfig(
            BudgetConfig(sessionId: session.id, slotId: nil, budgetCents: 200)
        )

        // Heavy burn rate: 300¢ over 1 hour
        let now = Date()
        try await recordSpend(slotId: slot.id, cents: 100, at: now.addingTimeInterval(-3600))
        try await recordSpend(slotId: slot.id, cents: 200, at: now)

        let projection = try await service.getProjection(sessionId: session.id)

        // Projected = current + 2 hours @ burn rate ≫ session budget of 200
        XCTAssertTrue(projection.overBudget,
                      "Heavy burn rate must flip overBudget true when projected > cap")
    }

    func test_getProjection_throwsWhenNoSessionConfig() async throws {
        let session = try await sessionRepo.createSession(
            CockpitSession(projectPath: "/tmp/budget-svc-noproj")
        )

        do {
            _ = try await service.getProjection(sessionId: session.id)
            XCTFail("Expected sessionConfigNotFound")
        } catch let error as BudgetServiceError {
            switch error {
            case .sessionConfigNotFound:
                break
            default:
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - applyThrottle

    func test_applyThrottle_levelsUpdateConfigAndRecordAlert() async throws {
        let (_, slot, cfg) = try await makeFixture(budgetCents: 1000)

        try await service.applyThrottle(slotId: slot.id, level: 1)

        let updated = try await budgetRepo.fetchConfigForSlot(slotId: slot.id)
        XCTAssertEqual(updated?.id, cfg.id)
        XCTAssertTrue(updated?.throttleEnabled == true, "Level 1 should enable throttle")

        let alerts = try await budgetRepo.fetchAlerts(configId: cfg.id)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertTrue(alerts[0].alertType.hasPrefix("throttle_"),
                      "Throttle audit alert should record action")
    }

    func test_applyThrottle_level3SetsHardStop() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000)

        try await service.applyThrottle(slotId: slot.id, level: 3)

        let updated = try await budgetRepo.fetchConfigForSlot(slotId: slot.id)
        XCTAssertTrue(updated?.hardStopEnabled == true, "Level 3 must enable hardStop")
        XCTAssertTrue(updated?.throttleEnabled == true)
    }

    func test_applyThrottle_rejectsInvalidLevel() async throws {
        let (_, slot, _) = try await makeFixture()

        do {
            try await service.applyThrottle(slotId: slot.id, level: 4)
            XCTFail("Expected invalidThrottleLevel")
        } catch let error as BudgetServiceError {
            switch error {
            case .invalidThrottleLevel(let lvl):
                XCTAssertEqual(lvl, 4)
            default:
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - autoThrottle

    func test_autoThrottle_picksLevel0WhenSpendLow() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000, warningThresholdPct: 80)
        try await recordSpend(slotId: slot.id, cents: 100) // 10%

        let level = try await service.autoThrottle(slotId: slot.id)

        XCTAssertEqual(level, 0, "Below warning threshold → no throttle")
    }

    func test_autoThrottle_picksLevel1AtWarning() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000, warningThresholdPct: 80)
        try await recordSpend(slotId: slot.id, cents: 850) // 85%

        let level = try await service.autoThrottle(slotId: slot.id)

        XCTAssertEqual(level, 1)
    }

    func test_autoThrottle_picksLevel3WhenExceeded() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1000)
        try await recordSpend(slotId: slot.id, cents: 1200) // 120%

        let level = try await service.autoThrottle(slotId: slot.id)

        XCTAssertEqual(level, 3, "Over budget must escalate to pause level")
    }

    // MARK: - routeModel

    func test_routeModel_picksHigherCapabilityWhenBudgetHealthy() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 10_000) // plenty of headroom
        try await recordSpend(slotId: slot.id, cents: 100)

        let recommendation = try await service.routeModel(slotId: slot.id, complexity: "complex")

        XCTAssertEqual(recommendation.budgetPressure, "none")
        XCTAssertGreaterThanOrEqual(recommendation.capabilityScore, 0.8,
                                    "Healthy budget should route to a high-capability model")
    }

    func test_routeModel_downgradesUnderBudgetPressure() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1_000)
        try await recordSpend(slotId: slot.id, cents: 950) // 95% — heavy pressure

        let recommendation = try await service.routeModel(slotId: slot.id, complexity: "moderate")

        XCTAssertNotEqual(recommendation.budgetPressure, "none",
                          "95% spend must register as budget pressure")
        XCTAssertFalse(recommendation.recommendedModel.isEmpty)
    }

    func test_routeModel_criticalPressureWhenExceeded() async throws {
        let (_, slot, _) = try await makeFixture(budgetCents: 1_000)
        try await recordSpend(slotId: slot.id, cents: 1_500) // 150%

        let recommendation = try await service.routeModel(slotId: slot.id, complexity: "simple")

        XCTAssertEqual(recommendation.budgetPressure, "critical")
    }
}
