import XCTest
import GRDB
@testable import XRoadsLib

/// US-003: Validates Chairman synthesis trigger and brief storage
final class ChairmanFeedServiceTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var repo: CockpitSessionRepository!
    private var bus: MessageBusService!
    private var mockSynthesizer: MockChairmanSynthesizer!
    private var feedService: ChairmanFeedService!

    // Shared test fixtures
    private var session: CockpitSession!
    private var slot1: AgentSlot!
    private var slot2: AgentSlot!

    /// Standard mock synthesis output
    private static let mockOutput = ChairmanSynthesisOutput(
        summary: "All agents progressing. Slot 0 working on login, Slot 1 on dashboard.",
        activeAgentsStatus: "2 agents active, 0 blocked",
        blockers: [],
        decisionsRecommended: ["Merge login branch first"],
        actionItems: ["Review PR #12", "Update tests"]
    )

    override func setUp() async throws {
        try await super.setUp()
        dbManager = try CockpitDatabaseManager()
        repo = await CockpitSessionRepository(databaseManager: dbManager)
        bus = await MessageBusService(databaseManager: dbManager)
        mockSynthesizer = MockChairmanSynthesizer(output: Self.mockOutput)

        session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/chairman-feed-test", status: .active)
        )
        slot1 = try await repo.createSlot(
            AgentSlot(
                cockpitSessionId: session.id,
                slotIndex: 0,
                agentType: "claude"
            )
        )
        slot2 = try await repo.createSlot(
            AgentSlot(
                cockpitSessionId: session.id,
                slotIndex: 1,
                agentType: "gemini"
            )
        )

        feedService = ChairmanFeedService(
            bus: bus,
            synthesizer: mockSynthesizer,
            repository: repo,
            dbQueue: await dbManager.dbQueue,
            synthesisThreshold: 5,
            debounceInterval: 0.0 // Disable debounce for tests
        )
    }

    override func tearDown() async throws {
        await feedService.stop()
        feedService = nil
        mockSynthesizer = nil
        bus = nil
        repo = nil
        dbManager = nil
        session = nil
        slot1 = nil
        slot2 = nil
        try await super.tearDown()
    }

    // MARK: - Should trigger synthesis after 5 new messages

    func test_triggersAfter5Messages() async throws {
        try await feedService.start(sessionId: session.id)

        // Publish 5 status messages to reach threshold
        for i in 0..<5 {
            let msg = AgentMessage(
                content: "Status update \(i)",
                messageType: .status,
                fromSlotId: slot1.id,
                isBroadcast: true
            )
            try await bus.publish(message: msg, fromSlot: slot1.id)
        }

        // Give the async stream time to process
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Verify synthesizer was called
        XCTAssertEqual(mockSynthesizer.callCount, 1, "Should trigger synthesis after 5 messages")

        // Verify chairman_brief was published to the bus
        let allMessages = try await bus.fetchMessages(sessionId: session.id)
        let briefs = allMessages.filter { $0.messageType == .chairmanBrief }
        XCTAssertEqual(briefs.count, 1, "Should publish one chairman_brief message")
        XCTAssertTrue(briefs.first!.isBroadcast, "chairman_brief should be broadcast")
    }

    // MARK: - Should trigger synthesis immediately on blocker message

    func test_triggersImmediatelyOnBlocker() async throws {
        try await feedService.start(sessionId: session.id)

        // Publish a single blocker message (should trigger immediately, not wait for 5)
        let blockerMsg = AgentMessage(
            content: "Blocked on merge conflict in feature/auth",
            messageType: .blocker,
            fromSlotId: slot2.id,
            isBroadcast: true
        )
        try await bus.publish(message: blockerMsg, fromSlot: slot2.id)

        // Give time to process
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        XCTAssertEqual(mockSynthesizer.callCount, 1, "Should trigger synthesis immediately on blocker")

        // Verify the input contains the blocker message
        let lastInput = mockSynthesizer.lastInput
        XCTAssertNotNil(lastInput)
        XCTAssertEqual(lastInput?.recentMessages.count, 1)
        XCTAssertEqual(lastInput?.recentMessages.first?.messageType, "blocker")
    }

    // MARK: - Should publish chairman_brief to message bus

    func test_publishesChairmanBriefToMessageBus() async throws {
        try await feedService.start(sessionId: session.id)

        // Trigger via blocker
        let msg = AgentMessage(
            content: "Blocked",
            messageType: .blocker,
            fromSlotId: slot1.id
        )
        try await bus.publish(message: msg, fromSlot: slot1.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        let allMessages = try await bus.fetchMessages(sessionId: session.id)
        let briefs = allMessages.filter { $0.messageType == .chairmanBrief }
        XCTAssertEqual(briefs.count, 1)

        // Verify brief content includes expected sections
        let briefContent = briefs.first!.content
        XCTAssertTrue(briefContent.contains("Status"), "Brief should include status section")
        XCTAssertTrue(briefContent.contains("Decisions Recommended"), "Brief should include decisions")
        XCTAssertTrue(briefContent.contains("Action Items"), "Brief should include action items")
    }

    // MARK: - Should update CockpitSession.chairman_brief in SQLite

    func test_updatesCockpitSessionChairmanBrief() async throws {
        try await feedService.start(sessionId: session.id)

        // Verify no brief initially
        let beforeSession = try await repo.fetchSession(id: session.id)
        XCTAssertNil(beforeSession?.chairmanBrief)

        // Trigger synthesis via blocker
        let msg = AgentMessage(
            content: "Need help with merge",
            messageType: .blocker,
            fromSlotId: slot1.id
        )
        try await bus.publish(message: msg, fromSlot: slot1.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify CockpitSession.chairmanBrief was updated
        let afterSession = try await repo.fetchSession(id: session.id)
        XCTAssertNotNil(afterSession?.chairmanBrief, "chairman_brief should be stored on session")
        XCTAssertTrue(afterSession!.chairmanBrief!.contains("Status"), "Stored brief should contain status")
    }

    // MARK: - Should not re-trigger on chairman_brief messages

    func test_doesNotRetriggerOnChairmanBriefMessages() async throws {
        try await feedService.start(sessionId: session.id)

        // Trigger first synthesis via blocker
        let blockerMsg = AgentMessage(
            content: "Blocked",
            messageType: .blocker,
            fromSlotId: slot1.id
        )
        try await bus.publish(message: blockerMsg, fromSlot: slot1.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockSynthesizer.callCount, 1)

        // The chairman_brief that was published should not trigger another synthesis.
        // Publish 3 more status messages (below threshold of 5).
        for i in 0..<3 {
            let msg = AgentMessage(
                content: "Follow-up \(i)",
                messageType: .status,
                fromSlotId: slot2.id
            )
            try await bus.publish(message: msg, fromSlot: slot2.id)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should still be 1 — the chairman_brief didn't count toward the threshold,
        // and only 3 new status messages isn't enough for threshold of 5
        XCTAssertEqual(mockSynthesizer.callCount, 1, "chairman_brief messages should not count toward synthesis threshold")
    }

    // MARK: - Brief includes required fields

    func test_briefIncludesAllRequiredFields() async throws {
        let outputWithBlockers = ChairmanSynthesisOutput(
            summary: "Project state summary",
            activeAgentsStatus: "2 active, 1 blocked",
            blockers: ["Merge conflict on feature/auth"],
            decisionsRecommended: ["Resolve conflict before continuing"],
            actionItems: ["Fix merge conflict", "Notify team lead"]
        )
        let synthesizerWithBlockers = MockChairmanSynthesizer(output: outputWithBlockers)
        let feed = ChairmanFeedService(
            bus: bus,
            synthesizer: synthesizerWithBlockers,
            repository: repo,
            dbQueue: await dbManager.dbQueue,
            synthesisThreshold: 5,
            debounceInterval: 0.0
        )

        try await feed.start(sessionId: session.id)

        let msg = AgentMessage(
            content: "Blocked on merge",
            messageType: .blocker,
            fromSlotId: slot1.id
        )
        try await bus.publish(message: msg, fromSlot: slot1.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        let allMessages = try await bus.fetchMessages(sessionId: session.id)
        let brief = allMessages.first { $0.messageType == .chairmanBrief }
        XCTAssertNotNil(brief)

        let content = brief!.content
        // AC: Brief includes active agents status, blockers, decisions recommended, action items
        XCTAssertTrue(content.contains("2 active, 1 blocked"), "Should include active agents status")
        XCTAssertTrue(content.contains("Merge conflict on feature/auth"), "Should include blockers")
        XCTAssertTrue(content.contains("Resolve conflict before continuing"), "Should include decisions")
        XCTAssertTrue(content.contains("Fix merge conflict"), "Should include action items")

        await feed.stop()
    }

    // MARK: - Debounce behavior

    func test_debouncePreventsTooFrequentSynthesis() async throws {
        // Create a feed service with debounce enabled (1 second)
        let debouncedFeed = ChairmanFeedService(
            bus: bus,
            synthesizer: mockSynthesizer,
            repository: repo,
            dbQueue: await dbManager.dbQueue,
            synthesisThreshold: 1, // Trigger on every message
            debounceInterval: 1.0  // 1 second debounce
        )

        try await debouncedFeed.start(sessionId: session.id)

        // Publish 3 messages rapidly
        for i in 0..<3 {
            let msg = AgentMessage(
                content: "Rapid message \(i)",
                messageType: .status,
                fromSlotId: slot1.id
            )
            try await bus.publish(message: msg, fromSlot: slot1.id)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Only the first message should have triggered synthesis (debounce blocks subsequent)
        XCTAssertEqual(mockSynthesizer.callCount, 1, "Debounce should prevent multiple rapid synthesis calls")

        await debouncedFeed.stop()
    }
}
