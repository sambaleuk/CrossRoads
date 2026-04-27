import XCTest
@testable import XRoadsLib

/// US-000 (B0): BrainProcessRegistry guards against parallel cockpit-brain spawns.
/// These tests use a per-test temp directory to avoid touching ~/Library/Application Support/XRoads
/// and cover the singleton/cleanup contract described in _CODE/prd.json US-000.
final class BrainProcessRegistryTests: XCTestCase {

    private var tempDir: URL!
    private var registry: BrainProcessRegistry!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainProcessRegistryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        registry = BrainProcessRegistry(directoryURL: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        registry = nil
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - Acceptance Criterion 1: write PID file on spawn

    func test_register_writesPidFileForProject() async throws {
        let project = "/tmp/some/project/A"
        let myPid = ProcessInfo.processInfo.processIdentifier

        try await registry.register(pid: myPid, forProject: project)

        let entries = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let pidFiles = entries.filter { $0.lastPathComponent.hasPrefix("brain-") && $0.pathExtension == "pid" }
        XCTAssertEqual(pidFiles.count, 1, "register should create exactly one pid file for the project")

        let payload = try String(contentsOf: pidFiles[0], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(Int32(payload), myPid, "pid file content should be the registered pid")
    }

    // MARK: - Acceptance Criterion 2: refuse 2nd spawn when live PID exists

    func test_aliveExistingPid_returnsRegisteredPidWhenAlive() async throws {
        let project = "/tmp/some/project/B"
        let myPid = ProcessInfo.processInfo.processIdentifier  // we are alive by definition

        try await registry.register(pid: myPid, forProject: project)
        let alive = await registry.aliveExistingPid(forProject: project)

        XCTAssertEqual(alive, myPid, "registered alive pid should be returned")
    }

    // MARK: - Acceptance Criterion 3: stale PID file is cleaned up

    func test_aliveExistingPid_returnsNilAndCleansStaleEntry() async throws {
        let project = "/tmp/some/project/C"
        // PID 1 is launchd on macOS — we cannot signal it (EPERM), so it appears alive to us.
        // We need a PID that does NOT exist. Pick something deliberately huge.
        let deadPid: pid_t = 999_999

        try await registry.register(pid: deadPid, forProject: project)
        let result = await registry.aliveExistingPid(forProject: project)

        XCTAssertNil(result, "dead pid should not be reported as alive")

        // File should have been removed as a side effect
        let entries = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let pidFiles = entries.filter { $0.lastPathComponent.hasPrefix("brain-") && $0.pathExtension == "pid" }
        XCTAssertTrue(pidFiles.isEmpty, "stale pid file should be cleaned up after the alive check")
    }

    // MARK: - Acceptance Criterion 4: clear removes the file (no signal sent)

    func test_clear_removesPidFile() async throws {
        let project = "/tmp/some/project/D"
        try await registry.register(pid: ProcessInfo.processInfo.processIdentifier, forProject: project)
        await registry.clear(forProject: project)

        let entries = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let pidFiles = entries.filter { $0.lastPathComponent.hasPrefix("brain-") && $0.pathExtension == "pid" }
        XCTAssertTrue(pidFiles.isEmpty, "clear should remove the pid file")
    }

    // MARK: - Acceptance Criterion 5: startup sweep cleans stale entries from prior crashes

    func test_cleanStalePidFiles_removesDeadEntriesAndKeepsAlive() async throws {
        let myPid = ProcessInfo.processInfo.processIdentifier

        try await registry.register(pid: myPid, forProject: "/tmp/proj/alive-1")
        try await registry.register(pid: myPid, forProject: "/tmp/proj/alive-2")
        try await registry.register(pid: 999_998, forProject: "/tmp/proj/dead-1")
        try await registry.register(pid: 999_997, forProject: "/tmp/proj/dead-2")

        let cleaned = await registry.cleanStalePidFiles()
        XCTAssertEqual(cleaned, 2, "exactly the 2 dead pid files should be cleaned")

        let entries = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let pidFiles = entries.filter { $0.lastPathComponent.hasPrefix("brain-") && $0.pathExtension == "pid" }
        XCTAssertEqual(pidFiles.count, 2, "the 2 alive pid files should remain")
    }

    // MARK: - Distinct projects get distinct files (no collision)

    func test_distinctProjectPaths_produceDistinctPidFiles() async throws {
        let myPid = ProcessInfo.processInfo.processIdentifier
        try await registry.register(pid: myPid, forProject: "/tmp/proj/one")
        try await registry.register(pid: myPid, forProject: "/tmp/proj/two")

        let entries = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let pidFiles = entries.filter { $0.lastPathComponent.hasPrefix("brain-") && $0.pathExtension == "pid" }
        XCTAssertEqual(pidFiles.count, 2, "two different project paths should hash to two different pid files")
    }
}
