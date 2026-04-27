import XCTest
import GRDB
@testable import XRoadsLib

/// Tests for ConfigSnapshotRepository — versioned config snapshot storage with auto-version.
final class ConfigSnapshotRepositoryTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var sessionRepo: CockpitSessionRepository!
    private var repo: ConfigSnapshotRepository!

    override func setUp() async throws {
        dbManager = try CockpitDatabaseManager()
        let dbQueue = await dbManager.dbQueue
        sessionRepo = CockpitSessionRepository(dbQueue: dbQueue)
        repo = ConfigSnapshotRepository(dbQueue: dbQueue)
    }

    private func makeSession() async throws -> CockpitSession {
        try await sessionRepo.createSession(CockpitSession(projectPath: "/tmp/snap-test"))
    }

    // MARK: - Versioning

    func test_createSnapshot_assignsVersionOneOnFirst() async throws {
        let session = try await makeSession()
        let snap = ConfigSnapshot(
            sessionId: session.id,
            configType: "agent_runtime",
            version: 0,  // ignored — repo recomputes
            data: "{\"runtime\":\"claude\"}"
        )

        let created = try await repo.createSnapshot(snap)
        XCTAssertEqual(created.version, 1)
    }

    func test_createSnapshot_incrementsVersionPerSessionAndType() async throws {
        let session = try await makeSession()
        for _ in 0..<3 {
            _ = try await repo.createSnapshot(ConfigSnapshot(
                sessionId: session.id,
                configType: "skill_loadout",
                version: 0,
                data: "{}"
            ))
        }
        let snapshots = try await repo.fetchSnapshots(sessionId: session.id, configType: "skill_loadout")
        XCTAssertEqual(snapshots.map(\.version), [3, 2, 1])
    }

    func test_createSnapshot_versioningIsIsolatedAcrossConfigType() async throws {
        let session = try await makeSession()
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "type-a", version: 0, data: "{}"))
        let bSnap = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "type-b", version: 0, data: "{}"))
        XCTAssertEqual(bSnap.version, 1)
    }

    // MARK: - Fetch by version

    func test_fetchByVersion_returnsExactMatch() async throws {
        let session = try await makeSession()
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "t", version: 0, data: "v1-data"))
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "t", version: 0, data: "v2-data"))

        let fetched = try await repo.fetchByVersion(sessionId: session.id, configType: "t", version: 1)
        XCTAssertEqual(fetched?.data, "v1-data")
    }

    func test_fetchByVersion_unknownVersion_returnsNil() async throws {
        let session = try await makeSession()
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "t", version: 0, data: "{}"))

        let fetched = try await repo.fetchByVersion(sessionId: session.id, configType: "t", version: 999)
        XCTAssertNil(fetched)
    }

    // MARK: - getLatest

    func test_getLatest_returnsHighestVersion() async throws {
        let session = try await makeSession()
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "t", version: 0, data: "first"))
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "t", version: 0, data: "second"))
        _ = try await repo.createSnapshot(ConfigSnapshot(sessionId: session.id, configType: "t", version: 0, data: "third"))

        let latest = try await repo.getLatest(sessionId: session.id, configType: "t")
        XCTAssertEqual(latest?.data, "third")
        XCTAssertEqual(latest?.version, 3)
    }

    func test_getLatest_emptyHistory_returnsNil() async throws {
        let session = try await makeSession()
        let latest = try await repo.getLatest(sessionId: session.id, configType: "anything")
        XCTAssertNil(latest)
    }
}
