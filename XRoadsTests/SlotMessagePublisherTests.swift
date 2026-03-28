import XCTest
import GRDB
@testable import XRoadsLib

/// US-002: Validates structured message extraction from agent stdout
final class SlotMessagePublisherTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var repo: CockpitSessionRepository!
    private var bus: MessageBusService!
    private var publisher: SlotMessagePublisher!

    // Shared test fixtures
    private var session: CockpitSession!
    private var slot: AgentSlot!

    override func setUp() async throws {
        try await super.setUp()
        dbManager = try CockpitDatabaseManager()
        repo = await CockpitSessionRepository(databaseManager: dbManager)
        bus = await MessageBusService(databaseManager: dbManager)
        publisher = SlotMessagePublisher(bus: bus, dbQueue: await dbManager.dbQueue)

        session = try await repo.createSession(
            CockpitSession(projectPath: "/tmp/publisher-test", status: .active)
        )
        slot = try await repo.createSlot(
            AgentSlot(
                cockpitSessionId: session.id,
                slotIndex: 0,
                agentType: "claude"
            )
        )
    }

    override func tearDown() async throws {
        publisher = nil
        bus = nil
        repo = nil
        dbManager = nil
        session = nil
        slot = nil
        try await super.tearDown()
    }

    // MARK: - PTYOutputParser: detect [XROADS:] prefix

    func test_parser_detectsXROADSPrefix() {
        let parser = PTYOutputParser()
        let line = """
        Some output [XROADS:{"type":"status","content":"Working on feature X"}] more text
        """
        let payload = parser.parse(line: line)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.type, "status")
        XCTAssertEqual(payload?.content, "Working on feature X")
    }

    func test_parser_returnsNilForNonXROADSLine() {
        let parser = PTYOutputParser()
        let line = "Just regular stdout output with no special markers"
        let payload = parser.parse(line: line)
        XCTAssertNil(payload)
    }

    func test_parser_returnsNilForMalformedJSON() {
        let parser = PTYOutputParser()
        let line = "[XROADS:not valid json]"
        let payload = parser.parse(line: line)
        XCTAssertNil(payload)
    }

    // MARK: - Parse JSON payload and create AgentMessage

    func test_processOutput_parsesAndPublishesMessage() async throws {
        let stdout = "[XROADS:{\"type\":\"blocker\",\"content\":\"Blocked on merge conflict\"}]\n"

        await publisher.processOutput(text: stdout, slotId: slot.id)

        let messages = try await bus.fetchMessages(slotId: slot.id)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.messageType, .blocker)
        XCTAssertEqual(messages.first?.content, "Blocked on merge conflict")
        XCTAssertEqual(messages.first?.fromSlotId, slot.id)
    }

    // MARK: - Publish message to MessageBusService

    func test_processOutput_publishesToBusAndNotifiesSubscribers() async throws {
        let stream = await bus.subscribe(toSession: session.id)
        var iterator = stream.makeAsyncIterator()

        let stdout = "[XROADS:{\"type\":\"completion\",\"content\":\"Feature done\"}]\n"
        await publisher.processOutput(text: stdout, slotId: slot.id)

        let received = await iterator.next()
        XCTAssertNotNil(received)
        XCTAssertEqual(received?.messageType, .completion)
        XCTAssertEqual(received?.content, "Feature done")
    }

    // MARK: - Update AgentSlot.currentTask on status message

    func test_processOutput_updatesCurrentTaskOnStatusMessage() async throws {
        let stdout = "[XROADS:{\"type\":\"status\",\"content\":\"Implementing login flow\"}]\n"

        await publisher.processOutput(text: stdout, slotId: slot.id)

        let updatedSlot = try await repo.fetchSlot(id: slot.id)
        XCTAssertEqual(updatedSlot?.currentTask, "Implementing login flow")
    }

    func test_processOutput_doesNotUpdateCurrentTaskOnNonStatusMessage() async throws {
        let stdout = "[XROADS:{\"type\":\"blocker\",\"content\":\"Blocked on dependency\"}]\n"

        await publisher.processOutput(text: stdout, slotId: slot.id)

        let updatedSlot = try await repo.fetchSlot(id: slot.id)
        XCTAssertNil(updatedSlot?.currentTask)
    }

    // MARK: - Multi-line parsing

    func test_processOutput_handlesMultipleMessagesInOneChunk() async throws {
        let stdout = """
        Regular output line
        [XROADS:{"type":"status","content":"Starting task"}]
        More output
        [XROADS:{"type":"question","content":"Should I use async?"}]
        """

        await publisher.processOutput(text: stdout, slotId: slot.id)

        let messages = try await bus.fetchMessages(slotId: slot.id)
        XCTAssertEqual(messages.count, 2)

        let types = Set(messages.map(\.messageType))
        XCTAssertTrue(types.contains(.status))
        XCTAssertTrue(types.contains(.question))
    }

    // MARK: - Unknown type handling

    func test_processOutput_skipsUnknownMessageType() async throws {
        let stdout = "[XROADS:{\"type\":\"unknown_type\",\"content\":\"Should be ignored\"}]\n"

        await publisher.processOutput(text: stdout, slotId: slot.id)

        let messages = try await bus.fetchMessages(slotId: slot.id)
        XCTAssertEqual(messages.count, 0)
    }
}
