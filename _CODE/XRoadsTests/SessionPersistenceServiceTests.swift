import XCTest
@testable import XRoadsLib

/// Tests for SessionPersistenceService — JSON-backed per-repo session metadata.
///
/// Uses a fresh temp directory per test so the on-disk side effects are isolated.
/// The service writes `<repoPath>/.crossroads/sessions.json` and adds `.crossroads/`
/// to the repo's `.gitignore`.
final class SessionPersistenceServiceTests: XCTestCase {

    private var service: SessionPersistenceService!
    private var tempRepo: URL!

    override func setUp() async throws {
        service = SessionPersistenceService()
        tempRepo = try makeTempRepo()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRepo)
    }

    // MARK: - Helpers

    private func makeTempRepo() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xroads-session-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSession(name: String = "main") -> Session {
        Session(name: name, repoPath: tempRepo.path)
    }

    // MARK: - Save / load roundtrip

    func test_saveSession_thenLoadSessions_roundtrip() async throws {
        let session = makeSession(name: "feat-auth")
        try await service.saveSession(session)

        let loaded = try await service.loadSessions(for: tempRepo.path)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "feat-auth")
    }

    func test_saveSession_writesGitignoreEntry() async throws {
        try await service.saveSession(makeSession())

        let gitignorePath = tempRepo.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: gitignorePath.path) {
            let contents = try String(contentsOf: gitignorePath, encoding: .utf8)
            XCTAssertTrue(contents.contains(".crossroads/"))
        }
        // Service ensures dir exists either way
        let crossroadsDir = tempRepo.appendingPathComponent(".crossroads")
        XCTAssertTrue(FileManager.default.fileExists(atPath: crossroadsDir.path))
    }

    func test_saveSession_secondCallUpserts() async throws {
        var session = makeSession(name: "v1")
        try await service.saveSession(session)
        session.name = "v2"
        try await service.saveSession(session)

        let loaded = try await service.loadSessions(for: tempRepo.path)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "v2")
    }

    func test_saveSession_invalidRepoPath_throws() async throws {
        let session = Session(name: "no-repo", repoPath: nil)
        do {
            try await service.saveSession(session)
            XCTFail("Expected invalidRepoPath")
        } catch SessionPersistenceError.invalidRepoPath {
            // expected
        }
    }

    // MARK: - lastSession

    func test_lastSession_returnsMostRecentlyUpdated() async throws {
        var older = makeSession(name: "older")
        older.updatedAt = Date().addingTimeInterval(-100)
        var newer = makeSession(name: "newer")
        newer.updatedAt = Date()

        try await service.saveSession(older)
        try await service.saveSession(newer)

        let last = try await service.lastSession(for: tempRepo.path)
        XCTAssertEqual(last?.name, "newer")
    }

    func test_lastSession_emptyRepo_returnsNil() async throws {
        let last = try await service.lastSession(for: tempRepo.path)
        XCTAssertNil(last)
    }

    // MARK: - updateHandoff / updateConversationId

    func test_updateHandoff_replacesPayloadAndBumpsUpdatedAt() async throws {
        let session = makeSession()
        try await service.saveSession(session)
        let before = (try await service.loadSessions(for: tempRepo.path)).first!
        // SessionPersistenceService persists with .iso8601 (second precision) — sleep across a second boundary
        try await Task.sleep(nanoseconds: 1_100_000_000)

        try await service.updateHandoff(sessionId: session.id, repoPath: tempRepo.path, payload: "## Handoff\nresume here")

        let after = (try await service.loadSessions(for: tempRepo.path)).first!
        XCTAssertEqual(after.handoffPayload, "## Handoff\nresume here")
        XCTAssertGreaterThan(after.updatedAt, before.updatedAt)
    }

    func test_updateConversationId_writesPerAgent() async throws {
        let session = makeSession()
        try await service.saveSession(session)

        try await service.updateConversationId(sessionId: session.id, repoPath: tempRepo.path, agent: "claude", conversationId: "abc-123")
        try await service.updateConversationId(sessionId: session.id, repoPath: tempRepo.path, agent: "gemini", conversationId: "xyz-456")

        let after = (try await service.loadSessions(for: tempRepo.path)).first!
        XCTAssertEqual(after.conversationIds["claude"], "abc-123")
        XCTAssertEqual(after.conversationIds["gemini"], "xyz-456")
    }

    func test_updateHandoff_unknownSession_isNoOp() async throws {
        // Pre-create an unrelated session so the file exists
        try await service.saveSession(makeSession())

        try await service.updateHandoff(sessionId: UUID(), repoPath: tempRepo.path, payload: "ignored")

        let loaded = try await service.loadSessions(for: tempRepo.path)
        XCTAssertNil(loaded.first?.handoffPayload)
    }

    // MARK: - Edge: corrupt file

    func test_loadSessions_corruptFile_throwsReadFailed() async throws {
        let dir = tempRepo.appendingPathComponent(".crossroads")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sessions.json")
        try "not valid json".write(to: file, atomically: true, encoding: .utf8)

        do {
            _ = try await service.loadSessions(for: tempRepo.path)
            XCTFail("Expected readFailed")
        } catch SessionPersistenceError.readFailed {
            // expected
        }
    }
}
