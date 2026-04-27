import XCTest
import GRDB
@testable import XRoadsLib

/// Tests for ChatHistoryRepository — chat persistence, wake prompts, harness iterations.
///
/// In-memory GRDB per test (matching repo convention in CockpitSessionRepositoryTests).
/// In-memory SQLite is a real DB code path (full migrator, full schema, no mocks).
final class ChatHistoryRepositoryTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var sessionRepo: CockpitSessionRepository!
    private var repo: ChatHistoryRepository!

    override func setUp() async throws {
        dbManager = try CockpitDatabaseManager()
        let dbQueue = await dbManager.dbQueue
        sessionRepo = CockpitSessionRepository(dbQueue: dbQueue)
        repo = ChatHistoryRepository(dbQueue: dbQueue)
    }

    // MARK: - Helpers

    private func makeSession(path: String = "/tmp/chat-history-test") async throws -> CockpitSession {
        try await sessionRepo.createSession(CockpitSession(projectPath: path))
    }

    // MARK: - saveMessage / fetchHistory

    func test_saveMessage_thenFetchHistory_roundtrip() async throws {
        let session = try await makeSession()
        let entry = ChatHistoryEntry(
            sessionId: session.id,
            role: "user",
            content: "Hello orchestrator"
        )
        try await repo.saveMessage(entry)

        let history = try await repo.fetchHistory(sessionId: session.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content, "Hello orchestrator")
        XCTAssertEqual(history.first?.role, "user")
    }

    func test_fetchHistory_returnsChronologicalOrder() async throws {
        let session = try await makeSession()
        let now = Date()
        try await repo.saveMessage(ChatHistoryEntry(sessionId: session.id, role: "user", content: "first", createdAt: now))
        try await repo.saveMessage(ChatHistoryEntry(sessionId: session.id, role: "assistant", content: "second", createdAt: now.addingTimeInterval(1)))
        try await repo.saveMessage(ChatHistoryEntry(sessionId: session.id, role: "user", content: "third", createdAt: now.addingTimeInterval(2)))

        let history = try await repo.fetchHistory(sessionId: session.id)
        XCTAssertEqual(history.map(\.content), ["first", "second", "third"])
    }

    func test_fetchHistory_isolatesPerSession() async throws {
        let s1 = try await makeSession(path: "/tmp/proj-a")
        let s2 = try await makeSession(path: "/tmp/proj-b")
        try await repo.saveMessage(ChatHistoryEntry(sessionId: s1.id, role: "user", content: "in A"))
        try await repo.saveMessage(ChatHistoryEntry(sessionId: s2.id, role: "user", content: "in B"))

        let aHistory = try await repo.fetchHistory(sessionId: s1.id)
        XCTAssertEqual(aHistory.count, 1)
        XCTAssertEqual(aHistory.first?.content, "in A")
    }

    func test_fetchHistory_respectsLimit() async throws {
        let session = try await makeSession()
        for i in 0..<10 {
            try await repo.saveMessage(ChatHistoryEntry(
                sessionId: session.id,
                role: "user",
                content: "msg \(i)",
                createdAt: Date().addingTimeInterval(TimeInterval(i))
            ))
        }
        let limited = try await repo.fetchHistory(sessionId: session.id, limit: 3)
        XCTAssertEqual(limited.count, 3)
    }

    // MARK: - saveMessages (batch)

    func test_saveMessages_persistsAllInOneTransaction() async throws {
        let session = try await makeSession()
        let entries = (0..<5).map { i in
            ChatHistoryEntry(sessionId: session.id, role: "user", content: "batch-\(i)")
        }
        try await repo.saveMessages(entries)

        let fetched = try await repo.fetchHistory(sessionId: session.id)
        XCTAssertEqual(fetched.count, 5)
    }

    // MARK: - fetchRecent

    func test_fetchRecent_returnsAcrossSessionsInChronologicalOrder() async throws {
        let s1 = try await makeSession(path: "/tmp/r1")
        let s2 = try await makeSession(path: "/tmp/r2")
        let now = Date()
        try await repo.saveMessage(ChatHistoryEntry(sessionId: s1.id, role: "user", content: "old", createdAt: now))
        try await repo.saveMessage(ChatHistoryEntry(sessionId: s2.id, role: "user", content: "newer", createdAt: now.addingTimeInterval(10)))

        let recent = try await repo.fetchRecent(limit: 10)
        XCTAssertEqual(recent.map(\.content), ["old", "newer"])
    }

    // MARK: - Cascade delete

    func test_deletingSession_cascadesAndRemovesChatHistory() async throws {
        let session = try await makeSession()
        try await repo.saveMessage(ChatHistoryEntry(sessionId: session.id, role: "user", content: "doomed"))
        let beforeCount = try await repo.fetchHistory(sessionId: session.id).count
        XCTAssertEqual(beforeCount, 1)

        try await sessionRepo.deleteSession(id: session.id)

        let afterCount = try await repo.fetchHistory(sessionId: session.id).count
        XCTAssertEqual(afterCount, 0)
    }

    // MARK: - buildChatSummary

    func test_buildChatSummary_emptyHistory_returnsNoHistoryString() async throws {
        let summary = try await repo.buildChatSummary(sessionId: nil, maxMessages: 10)
        XCTAssertTrue(summary.contains("No chat history"))
    }

    func test_buildChatSummary_truncatesLongMessages() async throws {
        let session = try await makeSession()
        let longContent = String(repeating: "x", count: 600)
        try await repo.saveMessage(ChatHistoryEntry(sessionId: session.id, role: "user", content: longContent))

        let summary = try await repo.buildChatSummary(sessionId: session.id, maxMessages: 10)
        XCTAssertTrue(summary.contains("..."))
        XCTAssertFalse(summary.contains(longContent))
    }

    // MARK: - Wake prompts

    func test_saveWakePrompt_thenFetchLatest_roundtrip() async throws {
        let session = try await makeSession()
        let prompt = CockpitWakePrompt(
            sessionId: session.id,
            prompt: "Resume from slot 3 retry",
            observations: "{\"slot3\":\"failed\"}",
            pendingActions: "[\"retry\"]"
        )
        try await repo.saveWakePrompt(prompt)

        let fetched = try await repo.fetchLatestWakePrompt(sessionId: session.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.prompt, "Resume from slot 3 retry")
    }

    func test_fetchLatestWakePrompt_returnsMostRecentBySession() async throws {
        let session = try await makeSession()
        try await repo.saveWakePrompt(CockpitWakePrompt(sessionId: session.id, prompt: "older", createdAt: Date().addingTimeInterval(-100)))
        try await repo.saveWakePrompt(CockpitWakePrompt(sessionId: session.id, prompt: "newer", createdAt: Date()))

        let fetched = try await repo.fetchLatestWakePrompt(sessionId: session.id)
        XCTAssertEqual(fetched?.prompt, "newer")
    }

    // MARK: - Harness iterations

    func test_saveHarnessIteration_andFetchPending_excludesApplied() async throws {
        let session = try await makeSession()
        let pending = HarnessIteration(sessionId: session.id, target: "skill:prd", critique: "missing tests", proposal: "add tests")
        let applied = HarnessIteration(sessionId: session.id, target: "skill:prd", critique: "old", proposal: "old", applied: true)
        try await repo.saveHarnessIteration(pending)
        try await repo.saveHarnessIteration(applied)

        let pendingResults = try await repo.fetchPendingProposals()
        XCTAssertEqual(pendingResults.count, 1)
        XCTAssertEqual(pendingResults.first?.critique, "missing tests")
    }

    func test_markApplied_setsFlagAndImpact() async throws {
        let session = try await makeSession()
        let iteration = HarnessIteration(sessionId: session.id, target: "skill:prd", critique: "x", proposal: "y")
        try await repo.saveHarnessIteration(iteration)

        try await repo.markApplied(id: iteration.id, impact: "{\"throughput\":+0.2}")

        let pending = try await repo.fetchPendingProposals()
        XCTAssertEqual(pending.count, 0)
        let allForTarget = try await repo.fetchProposalsForTarget("skill:prd")
        XCTAssertEqual(allForTarget.first?.impact, "{\"throughput\":+0.2}")
        XCTAssertEqual(allForTarget.first?.applied, true)
    }
}
