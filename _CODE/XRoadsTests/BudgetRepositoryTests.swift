import XCTest
import GRDB
@testable import XRoadsLib

/// Unit tests for `BudgetRepository`.
///
/// Covers PRD-S02 / US-001 acceptance criteria:
///   - BudgetConfig CRUD (session-level + slot-level)
///   - BudgetAlert insert + fetch + acknowledge
///   - cascade delete via FK on cockpit_session / agent_slot
final class BudgetRepositoryTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var sessionRepo: CockpitSessionRepository!
    private var repo: BudgetRepository!

    override func setUp() async throws {
        dbManager = try CockpitDatabaseManager() // in-memory
        let dbQueue = await dbManager.dbQueue
        sessionRepo = CockpitSessionRepository(dbQueue: dbQueue)
        repo = BudgetRepository(dbQueue: dbQueue)
    }

    // MARK: - Helpers

    private func makeSession() async throws -> CockpitSession {
        try await sessionRepo.createSession(
            CockpitSession(projectPath: "/tmp/budget-test-\(UUID().uuidString)")
        )
    }

    private func makeSlot(in session: CockpitSession, index: Int = 0) async throws -> AgentSlot {
        try await sessionRepo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: index, agentType: "claude")
        )
    }

    // MARK: - Config CRUD

    func test_createConfig_persistsRecord() async throws {
        let session = try await makeSession()
        let config = BudgetConfig(sessionId: session.id, budgetCents: 5000)

        let saved = try await repo.createConfig(config)

        XCTAssertEqual(saved.id, config.id, "Saved config should keep its id")
        XCTAssertEqual(saved.budgetCents, 5000)
    }

    func test_fetchConfigForSession_returnsSessionLevelConfigOnly() async throws {
        let session = try await makeSession()
        let slot = try await makeSlot(in: session)

        let sessionLevel = BudgetConfig(sessionId: session.id, slotId: nil, budgetCents: 2500)
        let slotLevel = BudgetConfig(sessionId: session.id, slotId: slot.id, budgetCents: 750)
        _ = try await repo.createConfig(sessionLevel)
        _ = try await repo.createConfig(slotLevel)

        let result = try await repo.fetchConfigForSession(sessionId: session.id)

        XCTAssertNotNil(result, "Should return session-level config")
        XCTAssertEqual(result?.budgetCents, 2500)
        XCTAssertNil(result?.slotId, "Session-level config must have nil slotId")
    }

    func test_fetchConfigForSlot_returnsSlotConfig() async throws {
        let session = try await makeSession()
        let slot = try await makeSlot(in: session)

        let slotConfig = BudgetConfig(sessionId: session.id, slotId: slot.id, budgetCents: 750)
        _ = try await repo.createConfig(slotConfig)

        let result = try await repo.fetchConfigForSlot(slotId: slot.id)

        XCTAssertEqual(result?.id, slotConfig.id)
        XCTAssertEqual(result?.budgetCents, 750)
    }

    func test_fetchConfig_returnsNilWhenAbsent() async throws {
        let session = try await makeSession()
        let result = try await repo.fetchConfigForSession(sessionId: session.id)
        XCTAssertNil(result)
    }

    func test_updateConfig_persistsChangesAndBumpsTimestamp() async throws {
        let session = try await makeSession()
        var config = BudgetConfig(sessionId: session.id, budgetCents: 1000)
        config = try await repo.createConfig(config)
        let originalUpdatedAt = config.updatedAt

        // Allow clock to advance so updatedAt diff is observable
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        config.budgetCents = 4200
        let updated = try await repo.updateConfig(config)

        XCTAssertEqual(updated.budgetCents, 4200)
        XCTAssertGreaterThan(updated.updatedAt.timeIntervalSince1970,
                             originalUpdatedAt.timeIntervalSince1970,
                             "updateConfig must refresh updatedAt")

        // Re-fetch confirms persistence
        let refetched = try await repo.fetchConfigForSession(sessionId: session.id)
        XCTAssertEqual(refetched?.budgetCents, 4200)
    }

    // MARK: - Alerts

    func test_createAlert_thenFetchAlerts() async throws {
        let session = try await makeSession()
        let config = try await repo.createConfig(
            BudgetConfig(sessionId: session.id, budgetCents: 1000)
        )

        let alert = BudgetAlert(
            budgetConfigId: config.id,
            alertType: "warning",
            currentSpendCents: 800,
            budgetCents: 1000,
            percentUsed: 80.0,
            message: "80% used"
        )
        _ = try await repo.createAlert(alert)

        let alerts = try await repo.fetchAlerts(configId: config.id)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.alertType, "warning")
        XCTAssertFalse(alerts.first?.acknowledged ?? true)
    }

    func test_fetchAlerts_returnsNewestFirst() async throws {
        let session = try await makeSession()
        let config = try await repo.createConfig(
            BudgetConfig(sessionId: session.id, budgetCents: 1000)
        )

        let now = Date()
        let older = BudgetAlert(
            budgetConfigId: config.id,
            alertType: "warning",
            currentSpendCents: 800,
            budgetCents: 1000,
            percentUsed: 80.0,
            message: "older",
            createdAt: now.addingTimeInterval(-10)
        )
        let newer = BudgetAlert(
            budgetConfigId: config.id,
            alertType: "hard_stop",
            currentSpendCents: 1100,
            budgetCents: 1000,
            percentUsed: 110.0,
            message: "newer",
            createdAt: now
        )
        _ = try await repo.createAlert(older)
        _ = try await repo.createAlert(newer)

        let alerts = try await repo.fetchAlerts(configId: config.id)

        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts.first?.message, "newer", "Newest alert should be first")
        XCTAssertEqual(alerts.last?.message, "older")
    }

    func test_acknowledgeAlert_setsAcknowledgedTrue() async throws {
        let session = try await makeSession()
        let config = try await repo.createConfig(
            BudgetConfig(sessionId: session.id, budgetCents: 1000)
        )
        let alert = try await repo.createAlert(BudgetAlert(
            budgetConfigId: config.id,
            alertType: "warning",
            currentSpendCents: 800,
            budgetCents: 1000,
            percentUsed: 80.0,
            message: "test"
        ))

        try await repo.acknowledgeAlert(id: alert.id)

        let after = try await repo.fetchAlerts(configId: config.id)
        XCTAssertEqual(after.count, 1)
        XCTAssertTrue(after[0].acknowledged, "Acknowledge must persist")
    }

    func test_acknowledgeAlert_throwsForUnknownId() async throws {
        do {
            try await repo.acknowledgeAlert(id: UUID())
            XCTFail("Expected acknowledgeAlert to throw alertNotFound")
        } catch let error as BudgetRepositoryError {
            switch error {
            case .alertNotFound:
                break // expected
            default:
                XCTFail("Expected alertNotFound, got \(error)")
            }
        }
    }

    // MARK: - Cascade Delete

    func test_cascadeDelete_removesConfigsAndAlertsWhenSessionDeleted() async throws {
        let session = try await makeSession()
        let slot = try await makeSlot(in: session)
        let config = try await repo.createConfig(
            BudgetConfig(sessionId: session.id, slotId: slot.id, budgetCents: 1000)
        )
        _ = try await repo.createAlert(BudgetAlert(
            budgetConfigId: config.id,
            alertType: "warning",
            currentSpendCents: 800,
            budgetCents: 1000,
            percentUsed: 80.0,
            message: "before delete"
        ))

        // Sanity: alert exists pre-delete
        let alertsBefore = try await repo.fetchAlerts(configId: config.id)
        XCTAssertEqual(alertsBefore.count, 1)

        // Delete session — should cascade through config → alert
        try await sessionRepo.deleteSession(id: session.id)

        let configAfter = try await repo.fetchConfigForSession(sessionId: session.id)
        XCTAssertNil(configAfter, "Session-level config should be cascade-deleted")

        let slotConfigAfter = try await repo.fetchConfigForSlot(slotId: slot.id)
        XCTAssertNil(slotConfigAfter, "Slot-level config should be cascade-deleted")

        let alertsAfter = try await repo.fetchAlerts(configId: config.id)
        XCTAssertEqual(alertsAfter.count, 0, "Alerts should be cascade-deleted with config")
    }

    // MARK: - Disambiguation

    func test_fetchConfig_disambiguatesBetweenSessionLevelAndSlotLevel() async throws {
        let session = try await makeSession()
        let slot = try await makeSlot(in: session)

        _ = try await repo.createConfig(
            BudgetConfig(sessionId: session.id, slotId: nil, budgetCents: 9000)
        )
        _ = try await repo.createConfig(
            BudgetConfig(sessionId: session.id, slotId: slot.id, budgetCents: 1500)
        )

        let sessionLevel = try await repo.fetchConfig(sessionId: session.id, slotId: nil)
        let slotLevel = try await repo.fetchConfig(sessionId: session.id, slotId: slot.id)

        XCTAssertEqual(sessionLevel?.budgetCents, 9000)
        XCTAssertEqual(slotLevel?.budgetCents, 1500)
        XCTAssertNotEqual(sessionLevel?.id, slotLevel?.id, "Different rows expected")
    }
}
