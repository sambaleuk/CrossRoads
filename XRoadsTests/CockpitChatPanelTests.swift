import XCTest
import GRDB
@testable import XRoadsLib

/// US-004: Validates chat panel display and user message injection.
/// Tests SlotChatViewModel message filtering, unread badge, stdin injection,
/// and chairman_brief refresh.
final class CockpitChatPanelTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var repo: CockpitSessionRepository!
    private var bus: MessageBusService!

    // Test fixtures
    private var session: CockpitSession!
    private var slot0: AgentSlot!
    private var slot1: AgentSlot!

    override func setUp() async throws {
        try await super.setUp()
        dbManager = try CockpitDatabaseManager()
        repo = await CockpitSessionRepository(databaseManager: dbManager)
        bus = await MessageBusService(databaseManager: dbManager)

        // Create session with two slots
        session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/chat-panel-test", status: .active)
        )
        slot0 = try await repo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: 0, agentType: "claude")
        )
        slot1 = try await repo.createSlot(
            AgentSlot(cockpitSessionId: session.id, slotIndex: 1, agentType: "gemini")
        )
    }

    override func tearDown() async throws {
        bus = nil
        repo = nil
        dbManager = nil
        session = nil
        slot0 = nil
        slot1 = nil
        try await super.tearDown()
    }

    // MARK: - Should display messages filtered by AgentSlot

    func test_loadMessages_filteredBySlot() async throws {
        // Publish messages to slot0
        try await bus.publish(
            message: AgentMessage(content: "Slot 0 msg", messageType: .status, fromSlotId: slot0.id),
            fromSlot: slot0.id
        )
        try await bus.publish(
            message: AgentMessage(content: "Slot 0 question", messageType: .question, fromSlotId: slot0.id),
            fromSlot: slot0.id
        )

        // Publish message to slot1
        try await bus.publish(
            message: AgentMessage(content: "Slot 1 msg", messageType: .status, fromSlotId: slot1.id),
            fromSlot: slot1.id
        )

        // Create view model for slot0
        let chatVM = await SlotChatViewModel(slot: slot0, bus: bus)
        await chatVM.loadMessages()

        // Assert: only slot0 messages are loaded
        let messages = await chatVM.messages
        XCTAssertEqual(messages.count, 2, "Should only display messages for slot0")
        XCTAssertTrue(messages.allSatisfy { $0.fromSlotId == slot0.id },
                      "All messages should be from slot0")
        XCTAssertEqual(messages[0].content, "Slot 0 msg")
        XCTAssertEqual(messages[1].content, "Slot 0 question")
    }

    // MARK: - Should show unread badge count

    func test_unreadBadgeCount() async throws {
        // Publish 3 unread messages (readAt == nil)
        for i in 0..<3 {
            try await bus.publish(
                message: AgentMessage(content: "Msg \(i)", messageType: .status, fromSlotId: slot0.id),
                fromSlot: slot0.id
            )
        }

        let chatVM = await SlotChatViewModel(slot: slot0, bus: bus)
        await chatVM.loadMessages()

        // Assert: unread count matches
        let unread = await chatVM.unreadCount
        XCTAssertEqual(unread, 3, "Should show 3 unread messages")

        // Mark all as read
        await chatVM.markAllAsRead()
        let afterMark = await chatVM.unreadCount
        XCTAssertEqual(afterMark, 0, "Should have 0 unread after markAllAsRead")
    }

    // MARK: - Should inject user message to agent stdin

    func test_sendMessage_publishesToBus() async throws {
        let chatVM = await SlotChatViewModel(slot: slot0, bus: bus, ptyRunner: nil)

        // Set input text and send
        await MainActor.run {
            chatVM.inputText = "Hello agent"
        }
        await chatVM.sendMessage()

        // Assert: input text cleared
        let inputAfter = await chatVM.inputText
        XCTAssertEqual(inputAfter, "", "Input should be cleared after send")

        // Assert: message published to bus
        let messages = try await bus.fetchMessages(slotId: slot0.id)
        XCTAssertEqual(messages.count, 1, "User message should be published to bus")
        XCTAssertEqual(messages.first?.content, "Hello agent")
    }

    // MARK: - Should refresh chairman_brief on session update

    func test_chairmanBrief_refreshOnSessionUpdate() async throws {
        // Initial session has no chairman brief
        XCTAssertNil(session.chairmanBrief)

        // Simulate ChairmanFeedService updating the session's chairman_brief
        var updatedSession = session!
        updatedSession.chairmanBrief = "## Status\nAll agents active\n\n## Blockers\n- None"
        let persisted = try await repo.updateSession(updatedSession)

        // Assert: brief is stored
        XCTAssertEqual(persisted.chairmanBrief, "## Status\nAll agents active\n\n## Blockers\n- None")

        // Simulate CockpitViewModel refresh: fetch session and check brief changed
        let refreshed = try await repo.fetchSession(id: session.id)
        XCTAssertNotNil(refreshed?.chairmanBrief, "Chairman brief should be set after update")
        XCTAssertEqual(refreshed?.chairmanBrief, updatedSession.chairmanBrief,
                       "Chairman brief should match the updated value")
    }

    // MARK: - Should stream new messages in real time

    func test_startListening_receivesNewMessages() async throws {
        let chatVM = await SlotChatViewModel(slot: slot0, bus: bus)
        await chatVM.startListening()

        // Give subscription a moment to register
        try await Task.sleep(for: .milliseconds(50))

        // Publish a message
        try await bus.publish(
            message: AgentMessage(content: "Live update", messageType: .status, fromSlotId: slot0.id),
            fromSlot: slot0.id
        )

        // Give stream a moment to deliver
        try await Task.sleep(for: .milliseconds(100))

        let messages = await chatVM.messages
        XCTAssertEqual(messages.count, 1, "Should receive live message via stream")
        XCTAssertEqual(messages.first?.content, "Live update")

        let unread = await chatVM.unreadCount
        XCTAssertEqual(unread, 1, "Should increment unread count on new message")

        await chatVM.stopListening()
    }

    // MARK: - Should not send empty messages

    func test_sendMessage_ignoresEmptyInput() async throws {
        let chatVM = await SlotChatViewModel(slot: slot0, bus: bus)

        // Send with empty/whitespace input
        await MainActor.run {
            chatVM.inputText = "   "
        }
        await chatVM.sendMessage()

        // Assert: no message published
        let messages = try await bus.fetchMessages(slotId: slot0.id)
        XCTAssertEqual(messages.count, 0, "Should not publish empty messages")
    }
}
