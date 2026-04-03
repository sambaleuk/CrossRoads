import XCTest
import GRDB
@testable import XRoadsLib

/// US-003: Validates Conductor Chairman integration and slot assignment
final class ConductorTests: XCTestCase {

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

    // MARK: - Test: should call cockpit-council with ChairmanInput and receive SlotAssignment

    func test_conductSlotAssignment_callsCouncilAndReceivesAssignments() async throws {
        // Arrange: mock Chairman returns 2 slot assignments
        let mockOutput = ChairmanOutput(
            decision: "Deploy 2 agents for parallel development",
            summary: "Frontend and backend tasks identified",
            assignments: [
                SlotAssignment(slotIndex: 0, skillName: "backend-dev", agentType: "claude", branch: "feat/api", taskDescription: "Implement REST API"),
                SlotAssignment(slotIndex: 1, skillName: "frontend-dev", agentType: "gemini", branch: "feat/ui", taskDescription: "Build React components")
            ]
        )
        let mockClient = MockCockpitCouncilClient(output: mockOutput)

        let conductor = ConductorService(
            councilClient: mockClient,
            repository: repo,
            lifecycleManager: lifecycleManager
        )

        // Create session in initializing state
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/conductor-test-\(UUID().uuidString)", status: .initializing)
        )

        let chairmanInput = ChairmanInput(
            gitLog: [],
            prdSummaries: [],
            openBranches: ["main"],
            lastSession: nil,
            projectPath: session.projectPath,
            suiteId: nil,
            collectedAt: Date()
        )

        // Act
        let (updatedSession, slots) = try await conductor.conductSlotAssignment(
            session: session,
            chairmanInput: chairmanInput
        )

        // Assert: slots created correctly
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].slotIndex, 0)
        XCTAssertEqual(slots[0].agentType, "claude")
        XCTAssertNotNil(slots[0].skillId)
        XCTAssertEqual(slots[0].branchName, "feat/api")

        XCTAssertEqual(slots[1].slotIndex, 1)
        XCTAssertEqual(slots[1].agentType, "gemini")
        XCTAssertNotNil(slots[1].skillId)
        XCTAssertEqual(slots[1].branchName, "feat/ui")

        // Assert: chairman brief stored on session
        XCTAssertEqual(updatedSession.chairmanBrief, "Frontend and backend tasks identified")

        // Assert: session transitioned to active
        XCTAssertEqual(updatedSession.status, .active)
    }

    // MARK: - Test: should create AgentSlot records from SlotAssignment

    func test_conductSlotAssignment_createsAgentSlotRecords() async throws {
        let mockOutput = ChairmanOutput(
            decision: "Single agent for focused work",
            summary: "One task identified",
            assignments: [
                SlotAssignment(slotIndex: 0, skillName: "code-reviewer", agentType: "claude", branch: "feat/review", taskDescription: "Review codebase")
            ]
        )
        let mockClient = MockCockpitCouncilClient(output: mockOutput)

        let conductor = ConductorService(
            councilClient: mockClient,
            repository: repo,
            lifecycleManager: lifecycleManager
        )

        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/slot-records-\(UUID().uuidString)", status: .initializing)
        )

        let chairmanInput = ChairmanInput(
            gitLog: [],
            prdSummaries: [],
            openBranches: ["main"],
            lastSession: nil,
            projectPath: session.projectPath,
            suiteId: nil,
            collectedAt: Date()
        )

        _ = try await conductor.conductSlotAssignment(session: session, chairmanInput: chairmanInput)

        // Verify slots are persisted in the database
        let persistedSlots = try await repo.fetchSlots(sessionId: session.id)
        XCTAssertEqual(persistedSlots.count, 1)
        XCTAssertEqual(persistedSlots[0].cockpitSessionId, session.id)
        XCTAssertEqual(persistedSlots[0].slotIndex, 0)
        XCTAssertEqual(persistedSlots[0].agentType, "claude")
        XCTAssertEqual(persistedSlots[0].branchName, "feat/review")

        // Verify the skill was created
        let skill = try await repo.findSkillByName("code-reviewer")
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.family, "cockpit-council")
    }

    // MARK: - Test: should transition session to active after assignment

    func test_conductSlotAssignment_transitionsSessionToActive() async throws {
        let mockOutput = ChairmanOutput(
            decision: "Ready to go",
            summary: "Tasks assigned",
            assignments: [
                SlotAssignment(slotIndex: 0, skillName: "test-writer", agentType: "claude", branch: "feat/tests", taskDescription: "Write tests")
            ]
        )
        let mockClient = MockCockpitCouncilClient(output: mockOutput)

        let conductor = ConductorService(
            councilClient: mockClient,
            repository: repo,
            lifecycleManager: lifecycleManager
        )

        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/transition-\(UUID().uuidString)", status: .initializing)
        )

        let chairmanInput = ChairmanInput(
            gitLog: [],
            prdSummaries: [],
            openBranches: ["main"],
            lastSession: nil,
            projectPath: session.projectPath,
            suiteId: nil,
            collectedAt: Date()
        )

        let (result, _) = try await conductor.conductSlotAssignment(session: session, chairmanInput: chairmanInput)

        // Session must be active
        XCTAssertEqual(result.status, .active)

        // Verify persisted state
        let persisted = try await repo.fetchSession(id: session.id)
        XCTAssertEqual(persisted?.status, .active)
    }

    // MARK: - Test: should reject if no slots assigned

    func test_conductSlotAssignment_rejectsIfNoSlotsAssigned() async throws {
        // Chairman returns empty assignments
        let mockOutput = ChairmanOutput(
            decision: "Nothing to do",
            summary: "No tasks found",
            assignments: []
        )
        let mockClient = MockCockpitCouncilClient(output: mockOutput)

        let conductor = ConductorService(
            councilClient: mockClient,
            repository: repo,
            lifecycleManager: lifecycleManager
        )

        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/no-slots-\(UUID().uuidString)", status: .initializing)
        )

        let chairmanInput = ChairmanInput(
            gitLog: [],
            prdSummaries: [],
            openBranches: ["main"],
            lastSession: nil,
            projectPath: session.projectPath,
            suiteId: nil,
            collectedAt: Date()
        )

        do {
            _ = try await conductor.conductSlotAssignment(session: session, chairmanInput: chairmanInput)
            XCTFail("Should have thrown noSlotsAssigned error")
        } catch let error as ConductorError {
            if case .noSlotsAssigned = error {
                // Expected: Conductor rejects empty assignments early
            } else {
                XCTFail("Wrong ConductorError variant: \(error)")
            }
        }
    }

    // MARK: - Test: state transition from initializing to active (states.json)

    func test_slotsAssigned_transitionsFromInitializingToActive() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/lifecycle-\(UUID().uuidString)", status: .initializing)
        )

        let slots = [
            AgentSlot(cockpitSessionId: session.id, slotIndex: 0, agentType: "claude", skillId: UUID())
        ]

        let result = try await lifecycleManager.assignSlots(session: session, slots: slots)
        XCTAssertEqual(result.status, .active)
    }

    // MARK: - Test: guard at_least_one_slot_configured blocks with no configured slots

    func test_slotsAssigned_blocksIfNoSlotConfigured() async throws {
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/guard-\(UUID().uuidString)", status: .initializing)
        )

        // Slots with no skillId — guard should block
        let slots = [
            AgentSlot(cockpitSessionId: session.id, slotIndex: 0, agentType: "claude", skillId: nil)
        ]

        do {
            _ = try await lifecycleManager.assignSlots(session: session, slots: slots)
            XCTFail("Should have thrown guardViolation for at_least_one_slot_configured")
        } catch let error as CockpitLifecycleError {
            if case .guardViolation(let guardName, let event) = error {
                XCTAssertEqual(guardName, "at_least_one_slot_configured")
                XCTAssertEqual(event, "slots_assigned")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Test: AgentSlot relation integrity (belongs_to CockpitSession)

    func test_agentSlotBelongsToCockpitSession() async throws {
        let mockOutput = ChairmanOutput(
            decision: "Test relation",
            summary: "Relation test",
            assignments: [
                SlotAssignment(slotIndex: 0, skillName: "relation-test", agentType: "claude", branch: "feat/rel", taskDescription: "Test")
            ]
        )
        let mockClient = MockCockpitCouncilClient(output: mockOutput)

        let conductor = ConductorService(
            councilClient: mockClient,
            repository: repo,
            lifecycleManager: lifecycleManager
        )

        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/relation-\(UUID().uuidString)", status: .initializing)
        )

        let chairmanInput = ChairmanInput(
            gitLog: [],
            prdSummaries: [],
            openBranches: ["main"],
            lastSession: nil,
            projectPath: session.projectPath,
            suiteId: nil,
            collectedAt: Date()
        )

        let (_, slots) = try await conductor.conductSlotAssignment(session: session, chairmanInput: chairmanInput)

        // Verify the slot belongs to the session
        XCTAssertEqual(slots[0].cockpitSessionId, session.id)

        // Verify via fetch
        let result = try await repo.fetchSessionWithSlots(id: session.id)
        XCTAssertNotNil(result)
        let (fetchedSession, fetchedSlots) = result!
        XCTAssertEqual(fetchedSession.id, session.id)
        XCTAssertEqual(fetchedSlots.count, 1)
        XCTAssertEqual(fetchedSlots[0].cockpitSessionId, session.id)
    }

    // MARK: - Test: invalid state transition (not in initializing)

    func test_conductSlotAssignment_rejectsWhenNotInitializing() async throws {
        let mockOutput = ChairmanOutput(
            decision: "Test",
            summary: "Test",
            assignments: [
                SlotAssignment(slotIndex: 0, skillName: "test", agentType: "claude", branch: "feat/x", taskDescription: "Test")
            ]
        )
        let mockClient = MockCockpitCouncilClient(output: mockOutput)

        let conductor = ConductorService(
            councilClient: mockClient,
            repository: repo,
            lifecycleManager: lifecycleManager
        )

        // Session in idle state — should reject
        let session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/wrong-state-\(UUID().uuidString)", status: .idle)
        )

        let chairmanInput = ChairmanInput(
            gitLog: [],
            prdSummaries: [],
            openBranches: ["main"],
            lastSession: nil,
            projectPath: session.projectPath,
            suiteId: nil,
            collectedAt: Date()
        )

        do {
            _ = try await conductor.conductSlotAssignment(session: session, chairmanInput: chairmanInput)
            XCTFail("Should have thrown sessionNotInitializing")
        } catch let error as ConductorError {
            if case .sessionNotInitializing(let status) = error {
                XCTAssertEqual(status, .idle)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}
