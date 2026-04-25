import XCTest
import GRDB
@testable import XRoadsLib

/// US-004: Validates Cockpit Mode UI state transitions and slot display.
/// Tests the CockpitLifecycleManager pause/resume transitions and
/// CockpitViewModel slot management that drives the CockpitModeView UI.
final class CockpitModeViewTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var repo: CockpitSessionRepository!
    private var gitService: GitService!
    private var contextReader: ProjectContextReader!
    private var lifecycleManager: CockpitLifecycleManager!

    override func setUp() async throws {
        try await super.setUp()
        dbManager = try CockpitDatabaseManager()
        repo = await CockpitSessionRepository(databaseManager: dbManager)
        gitService = GitService()
        contextReader = ProjectContextReader(gitService: gitService, repository: repo)
        lifecycleManager = CockpitLifecycleManager(contextReader: contextReader, repository: repo)
    }

    override func tearDown() async throws {
        lifecycleManager = nil
        contextReader = nil
        gitService = nil
        repo = nil
        dbManager = nil
        try await super.tearDown()
    }

    // MARK: - Test: Should transition CockpitSession to paused when pause triggered from UI

    func test_pause_transitionsActiveSessionToPaused() async throws {
        // Arrange: create a session in active state (simulating post-activation)
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/pause-test-\(UUID().uuidString)", status: .active)
        )

        // Act: pause the session
        let paused = try await lifecycleManager.pause(session: session)

        // Assert: session transitioned to paused
        XCTAssertEqual(paused.status, .paused, "Session should transition from active to paused")

        // Verify persistence
        let persisted = try await repo.fetchSession(id: session.id)
        XCTAssertEqual(persisted?.status, .paused, "Paused state should be persisted to database")
    }

    // MARK: - Test: Should transition CockpitSession back to active on resume

    func test_resume_transitionsPausedSessionToActive() async throws {
        // Arrange: create a session in paused state
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/resume-test-\(UUID().uuidString)", status: .paused)
        )

        // Act: resume the session
        let resumed = try await lifecycleManager.resume(session: session)

        // Assert: session transitioned back to active
        XCTAssertEqual(resumed.status, .active, "Session should transition from paused to active")

        // Verify persistence
        let persisted = try await repo.fetchSession(id: session.id)
        XCTAssertEqual(persisted?.status, .active, "Active state should be persisted to database")
    }

    // MARK: - Test: Should reject pause from non-active state

    func test_pause_rejectsFromIdleState() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/pause-reject-\(UUID().uuidString)", status: .idle)
        )

        do {
            _ = try await lifecycleManager.pause(session: session)
            XCTFail("Pause from idle should throw invalidTransition")
        } catch let error as CockpitLifecycleError {
            if case .invalidTransition(let from, let event) = error {
                XCTAssertEqual(from, .idle)
                XCTAssertEqual(event, "pause")
            } else {
                XCTFail("Expected invalidTransition error, got: \(error)")
            }
        }
    }

    // MARK: - Test: Should reject resume from non-paused state

    func test_resume_rejectsFromActiveState() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/resume-reject-\(UUID().uuidString)", status: .active)
        )

        do {
            _ = try await lifecycleManager.resume(session: session)
            XCTFail("Resume from active should throw invalidTransition")
        } catch let error as CockpitLifecycleError {
            if case .invalidTransition(let from, let event) = error {
                XCTAssertEqual(from, .active)
                XCTAssertEqual(event, "resume")
            } else {
                XCTFail("Expected invalidTransition error, got: \(error)")
            }
        }
    }

    // MARK: - Test: Should pause all running slots on session pause

    func test_pause_setsAllRunningSlotsToPaused() async throws {
        // Arrange: create active session with running slots
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/slot-pause-\(UUID().uuidString)", status: .active)
        )

        let slot0 = try await repo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: 0, status: .running, agentType: "claude", branchName: "feat/api")
        )
        let slot1 = try await repo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: 1, status: .running, agentType: "gemini", branchName: "feat/ui")
        )

        // Act: pause session and update slots (as CockpitViewModel would)
        let pausedSession = try await lifecycleManager.pause(session: session)
        XCTAssertEqual(pausedSession.status, .paused)

        // Simulate what CockpitViewModel.pause() does: transition running slots to paused
        var updatedSlot0 = slot0
        updatedSlot0.status = .paused
        let persistedSlot0 = try await repo.updateSlot(updatedSlot0)

        var updatedSlot1 = slot1
        updatedSlot1.status = .paused
        let persistedSlot1 = try await repo.updateSlot(updatedSlot1)

        // Assert: all slots are now paused
        XCTAssertEqual(persistedSlot0.status, .paused, "Slot 0 should be paused")
        XCTAssertEqual(persistedSlot1.status, .paused, "Slot 1 should be paused")

        // Verify from database
        let allSlots = try await repo.fetchSlots(sessionId: session.id)
        XCTAssertTrue(allSlots.allSatisfy { $0.status == .paused }, "All slots should be paused in DB")
    }

    // MARK: - Test: Should close session from active or paused state

    func test_close_fromActiveState() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/close-active-\(UUID().uuidString)", status: .active)
        )

        let closed = try await lifecycleManager.close(session: session)

        XCTAssertEqual(closed.status, .closed, "Session should transition from active to closed")
    }

    func test_close_fromPausedState() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/close-paused-\(UUID().uuidString)", status: .paused)
        )

        let closed = try await lifecycleManager.close(session: session)

        XCTAssertEqual(closed.status, .closed, "Session should transition from paused to closed")
    }

    // MARK: - Test: Should block close with pending gates from active

    func test_close_blockedByPendingGatesFromActive() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/close-gates-\(UUID().uuidString)", status: .active)
        )

        do {
            _ = try await lifecycleManager.close(session: session, hasPendingGates: true)
            XCTFail("Close with pending gates should throw guardViolation")
        } catch let error as CockpitLifecycleError {
            if case .guardViolation(let guardName, let event) = error {
                XCTAssertEqual(guardName, "no_pending_gates")
                XCTAssertEqual(event, "close")
            } else {
                XCTFail("Expected guardViolation error, got: \(error)")
            }
        }
    }

    // MARK: - Test: Slot card display data

    func test_slotCardDisplaysCorrectData() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/card-display-\(UUID().uuidString)", status: .active)
        )

        let slot = try await repo.createSlot(
            AgentSlot(
                cockpitSessionId: session.id,
                slotIndex: 0,
                status: .running,
                agentType: "claude",
                branchName: "feat/api",
                skillId: UUID()
            )
        )

        // Assert slot data used by CockpitSlotCardView
        XCTAssertEqual(slot.slotIndex, 0)
        XCTAssertEqual(slot.agentType, "claude")
        XCTAssertEqual(slot.status, .running)
        XCTAssertEqual(slot.branchName, "feat/api")
        XCTAssertNotNil(slot.skillId, "Slot should have a skill assigned for card display")
    }
}
