import XCTest
@testable import XRoadsLib

/// Tests for NotesSyncService — bidirectional notes sync between repo and worktree.
///
/// File-based; uses temp directories per test for isolation.
final class NotesSyncServiceTests: XCTestCase {

    private var service: NotesSyncService!
    private var tempRoot: URL!
    private var repoURL: URL!
    private var worktreeURL: URL!

    override func setUp() async throws {
        service = NotesSyncService()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xroads-notes-tests")
            .appendingPathComponent(UUID().uuidString)
        repoURL = tempRoot.appendingPathComponent("repo")
        worktreeURL = tempRoot.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeAssignment(branch: String = "feat/auth") -> WorktreeAssignment {
        WorktreeAssignment(
            id: UUID(),
            taskGroup: TaskGroup(id: "tg-1", preferredAgent: .claude, storyIds: [], estimatedComplexity: 1),
            agentType: .claude,
            branchName: branch,
            worktreePath: worktreeURL
        )
    }

    // MARK: - Sync forward (repo → worktree)

    func test_syncNotesToWorktree_seedsFilesInWorktreeFromRepoNotes() throws {
        let repoNotesDir = repoURL.appendingPathComponent("notes/feat-auth", isDirectory: true)
        try FileManager.default.createDirectory(at: repoNotesDir, withIntermediateDirectories: true)
        let decisionsFile = repoNotesDir.appendingPathComponent("decisions.md")
        try "# Decisions Log\n\n- pick-jwt".write(to: decisionsFile, atomically: true, encoding: .utf8)

        try service.syncNotesToWorktree(repoPath: repoURL, assignment: makeAssignment())

        let copied = worktreeURL.appendingPathComponent("notes").appendingPathComponent("decisions.md")
        let contents = try String(contentsOf: copied, encoding: .utf8)
        XCTAssertTrue(contents.contains("pick-jwt"))
    }

    func test_syncNotesToWorktree_createsHeaderWhenRepoFileMissing() throws {
        try service.syncNotesToWorktree(repoPath: repoURL, assignment: makeAssignment())

        let learningsInWorktree = worktreeURL.appendingPathComponent("notes").appendingPathComponent("learnings.md")
        let contents = try String(contentsOf: learningsInWorktree, encoding: .utf8)
        XCTAssertTrue(contents.contains("# Learnings Log"))
    }

    // MARK: - Sync back (worktree → repo)

    func test_syncNotesBack_appendsTimestampedSection() throws {
        // Set up worktree notes with content
        let worktreeNotesDir = worktreeURL.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: worktreeNotesDir, withIntermediateDirectories: true)
        try "session insight: cache TTL too high".write(
            to: worktreeNotesDir.appendingPathComponent("learnings.md"),
            atomically: true,
            encoding: .utf8
        )

        try service.syncNotesBack(repoPath: repoURL, assignment: makeAssignment())

        let repoLearnings = repoURL.appendingPathComponent("notes/feat-auth/learnings.md")
        let contents = try String(contentsOf: repoLearnings, encoding: .utf8)
        XCTAssertTrue(contents.contains("session insight: cache TTL too high"))
        XCTAssertTrue(contents.contains("feat/auth"))  // branch in section header
    }

    func test_syncNotesBack_skipsEmptyWorktreeFiles() throws {
        let worktreeNotesDir = worktreeURL.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: worktreeNotesDir, withIntermediateDirectories: true)
        try "   \n\n  ".write(
            to: worktreeNotesDir.appendingPathComponent("blockers.md"),
            atomically: true,
            encoding: .utf8
        )

        try service.syncNotesBack(repoPath: repoURL, assignment: makeAssignment())

        // Repo file should not exist (or contain only an empty header) — we should not have appended whitespace as a learning
        let repoBlockers = repoURL.appendingPathComponent("notes/feat-auth/blockers.md")
        if FileManager.default.fileExists(atPath: repoBlockers.path) {
            let contents = try String(contentsOf: repoBlockers, encoding: .utf8)
            XCTAssertFalse(contents.contains("##"))  // no timestamp section appended
        }
    }

    func test_syncNotesBack_missingWorktreeNotesDir_isNoOp() throws {
        XCTAssertNoThrow(try service.syncNotesBack(repoPath: repoURL, assignment: makeAssignment()))
    }

    // MARK: - Branch sanitization

    func test_branchWithSlash_sanitizesToDashedFolder() throws {
        let assignment = makeAssignment(branch: "feat/my-thing")
        let worktreeNotesDir = worktreeURL.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: worktreeNotesDir, withIntermediateDirectories: true)
        try "content".write(
            to: worktreeNotesDir.appendingPathComponent("decisions.md"),
            atomically: true,
            encoding: .utf8
        )

        try service.syncNotesBack(repoPath: repoURL, assignment: assignment)

        let expected = repoURL.appendingPathComponent("notes/feat-my-thing/decisions.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }
}
