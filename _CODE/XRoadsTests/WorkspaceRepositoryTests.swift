import XCTest
import GRDB
@testable import XRoadsLib

/// Tests for WorkspaceRepository — workspace CRUD + active-switching.
final class WorkspaceRepositoryTests: XCTestCase {

    private var dbManager: CockpitDatabaseManager!
    private var repo: WorkspaceRepository!

    override func setUp() async throws {
        dbManager = try CockpitDatabaseManager()
        let dbQueue = await dbManager.dbQueue
        repo = WorkspaceRepository(dbQueue: dbQueue)
    }

    private func makeWorkspace(name: String = "alpha", path: String = "/tmp/proj-alpha") -> Workspace {
        Workspace(name: name, projectPath: path)
    }

    // MARK: - Create / fetch

    func test_createWorkspace_persists() async throws {
        let ws = makeWorkspace()
        let created = try await repo.createWorkspace(ws)
        XCTAssertEqual(created.id, ws.id)

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.projectPath, "/tmp/proj-alpha")
    }

    func test_fetchAll_isOrderedByLastAccessedDesc() async throws {
        let now = Date()
        let older = Workspace(name: "older", projectPath: "/tmp/old", lastAccessedAt: now.addingTimeInterval(-100))
        let newer = Workspace(name: "newer", projectPath: "/tmp/new", lastAccessedAt: now)
        _ = try await repo.createWorkspace(older)
        _ = try await repo.createWorkspace(newer)

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.map(\.name), ["newer", "older"])
    }

    // MARK: - Active switching

    func test_switchActive_deactivatesOthersAndActivatesTarget() async throws {
        let a = try await repo.createWorkspace(Workspace(name: "a", projectPath: "/tmp/a", isActive: true))
        let b = try await repo.createWorkspace(Workspace(name: "b", projectPath: "/tmp/b", isActive: false))

        try await repo.switchActive(id: b.id)

        let active = try await repo.fetchActive()
        XCTAssertEqual(active?.id, b.id)
        XCTAssertEqual(active?.isActive, true)

        // a is no longer active — fetch by id
        let all = try await repo.fetchAll()
        let aFresh = all.first(where: { $0.id == a.id })
        XCTAssertEqual(aFresh?.isActive, false)
    }

    func test_switchActive_throwsForUnknownId() async throws {
        let unknownId = UUID()
        do {
            try await repo.switchActive(id: unknownId)
            XCTFail("Expected workspaceNotFound")
        } catch let WorkspaceRepositoryError.workspaceNotFound(id) {
            XCTAssertEqual(id, unknownId)
        }
    }

    // MARK: - Update / delete

    func test_updateWorkspace_refreshesLastAccessedAt() async throws {
        var ws = try await repo.createWorkspace(makeWorkspace())
        let originalAccess = ws.lastAccessedAt
        try await Task.sleep(nanoseconds: 5_000_000)  // 5ms — make timestamp drift observable
        ws.name = "renamed"

        let updated = try await repo.updateWorkspace(ws)

        XCTAssertEqual(updated.name, "renamed")
        XCTAssertGreaterThan(updated.lastAccessedAt, originalAccess)
    }

    func test_deleteWorkspace_removesRow() async throws {
        let ws = try await repo.createWorkspace(makeWorkspace())
        try await repo.deleteWorkspace(id: ws.id)

        let all = try await repo.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func test_deleteWorkspace_throwsForUnknownId() async throws {
        let unknownId = UUID()
        do {
            try await repo.deleteWorkspace(id: unknownId)
            XCTFail("Expected workspaceNotFound")
        } catch let WorkspaceRepositoryError.workspaceNotFound(id) {
            XCTAssertEqual(id, unknownId)
        }
    }
}
