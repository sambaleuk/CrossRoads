import XCTest
@testable import XRoadsLib

/// Tests for ConfigChecker — CLI tool availability detection + cache lifecycle.
///
/// Some tests run real `which` lookups (e.g. for git, which is essentially always
/// installed on dev machines). The cache lifecycle is tested independently of
/// real binaries.
final class ConfigCheckerTests: XCTestCase {

    private var checker: ConfigChecker!

    override func setUp() async throws {
        checker = ConfigChecker()
    }

    // MARK: - Smoke: real environment

    func test_checkGit_isAvailableOnDevMachine() async {
        let available = await checker.checkGit()
        XCTAssertTrue(available, "git is expected to be available on this machine")
    }

    func test_checkAll_returnsConfigStatusWithCheckedAt() async {
        let status = await checker.checkAll()
        // checkedAt should be recent
        XCTAssertLessThan(Date().timeIntervalSince(status.checkedAt), 5)
    }

    // MARK: - Cache lifecycle

    func test_checkAll_isCachedWithinDuration() async {
        let first = await checker.checkAll()
        let second = await checker.checkAll()  // should hit cache
        // Same checkedAt instance proves cache was used
        XCTAssertEqual(first.checkedAt, second.checkedAt)
    }

    func test_checkAll_forceRefresh_recomputes() async {
        let first = await checker.checkAll()
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms drift
        let refreshed = await checker.checkAll(forceRefresh: true)
        XCTAssertNotEqual(first.checkedAt, refreshed.checkedAt)
    }

    func test_clearCache_forcesRecompute() async {
        let first = await checker.checkAll()
        await checker.clearCache()
        try? await Task.sleep(nanoseconds: 10_000_000)
        let second = await checker.checkAll()
        XCTAssertNotEqual(first.checkedAt, second.checkedAt)
    }

    // MARK: - ConfigStatus computed properties (pure logic)

    func test_configStatus_anyAgentAvailable_truthTable() {
        let allOff = ConfigStatus(
            git: .available(tool: "git", path: "/usr/bin/git"),
            claude: .unavailable(tool: "claude"),
            gemini: .unavailable(tool: "gemini"),
            codex: .unavailable(tool: "codex"),
            checkedAt: Date()
        )
        XCTAssertFalse(allOff.anyAgentAvailable)

        let claudeOnly = ConfigStatus(
            git: .available(tool: "git", path: "/usr/bin/git"),
            claude: .available(tool: "claude", path: "/usr/local/bin/claude"),
            gemini: .unavailable(tool: "gemini"),
            codex: .unavailable(tool: "codex"),
            checkedAt: Date()
        )
        XCTAssertTrue(claudeOnly.anyAgentAvailable)
        XCTAssertEqual(claudeOnly.availableAgentTypes, [.claude])
    }

    func test_configStatus_summary_indicatesGitMissing() {
        let noGit = ConfigStatus(
            git: .unavailable(tool: "git"),
            claude: .available(tool: "claude", path: "/x"),
            gemini: .unavailable(tool: "gemini"),
            codex: .unavailable(tool: "codex"),
            checkedAt: Date()
        )
        XCTAssertTrue(noGit.summary.lowercased().contains("git"))
    }

    func test_configStatus_summary_indicatesNoAgents() {
        let noAgents = ConfigStatus(
            git: .available(tool: "git", path: "/usr/bin/git"),
            claude: .unavailable(tool: "claude"),
            gemini: .unavailable(tool: "gemini"),
            codex: .unavailable(tool: "codex"),
            checkedAt: Date()
        )
        XCTAssertTrue(noAgents.summary.lowercased().contains("agent"))
    }

    func test_configStatus_unavailableTools_listsMissing() {
        let mixed = ConfigStatus(
            git: .available(tool: "git", path: "/usr/bin/git"),
            claude: .available(tool: "claude", path: "/x"),
            gemini: .unavailable(tool: "gemini"),
            codex: .unavailable(tool: "codex"),
            checkedAt: Date()
        )
        XCTAssertEqual(mixed.unavailableTools, ["gemini", "codex"])
    }
}
