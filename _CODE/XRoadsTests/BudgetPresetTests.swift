import XCTest
@testable import XRoadsLib

/// Unit tests for `BudgetPreset` and `BudgetPresetManager` (PRD-S02 / US-006).
///
/// Covers acceptance criteria:
///   - Built-in presets exist with the contracted ids and shape
///   - Custom presets save → load round-trip via JSON on disk
///   - Built-in ids cannot be reused, edited, or deleted
///   - Materialize maps preset → BudgetConfig faithfully
///   - apply(presetId:) is the one-shot used by ConductorService on activation
final class BudgetPresetTests: XCTestCase {

    // MARK: - Per-test scratch dir

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xroads-budget-preset-tests-\(UUID().uuidString)",
                                   isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir, FileManager.default.fileExists(atPath: tmpDir.path) {
            try FileManager.default.removeItem(at: tmpDir)
        }
    }

    private func makeManager() -> BudgetPresetManager {
        let store = tmpDir.appendingPathComponent("budget-presets.json")
        return BudgetPresetManager(storeURL: store)
    }

    // MARK: - Built-in shape

    func test_builtinPresets_haveContractedIds() {
        let ids = BudgetPreset.builtin.map(\.id)
        XCTAssertEqual(ids, ["frugal", "standard", "performance", "unlimited"])
    }

    func test_builtinPresets_areAllMarkedBuiltin() {
        XCTAssertTrue(BudgetPreset.builtin.allSatisfy(\.isBuiltin))
    }

    func test_builtinPresets_haveMonotonicallyIncreasingBudgets() {
        let frugal = BudgetPreset.frugal.budgetCents
        let standard = BudgetPreset.standard.budgetCents
        let performance = BudgetPreset.performance.budgetCents
        let unlimited = BudgetPreset.unlimited.budgetCents
        XCTAssertLessThan(frugal, standard)
        XCTAssertLessThan(standard, performance)
        XCTAssertLessThan(performance, unlimited,
                          "Unlimited sentinel must exceed performance cap")
    }

    func test_unlimited_disablesHardStopAndThrottle() {
        XCTAssertFalse(BudgetPreset.unlimited.hardStop)
        XCTAssertFalse(BudgetPreset.unlimited.throttle)
        XCTAssertNil(BudgetPreset.unlimited.dailyLimitCents)
    }

    func test_reservedIds_matchBuiltinIds() {
        XCTAssertEqual(BudgetPreset.reservedIds,
                       Set(BudgetPreset.builtin.map(\.id)))
    }

    // MARK: - allPresets()

    func test_allPresets_returnsBuiltinsWhenStoreEmpty() async throws {
        let manager = makeManager()
        let all = try await manager.allPresets()
        XCTAssertEqual(all.count, BudgetPreset.builtin.count)
        XCTAssertEqual(all.map(\.id), BudgetPreset.builtin.map(\.id))
    }

    func test_allPresets_includesCustomAfterBuiltins() async throws {
        let manager = makeManager()
        let custom = BudgetPreset(
            id: "custom-tight",
            name: "Tight",
            budgetCents: 750,
            warningPct: 60,
            hardStop: true,
            throttle: true,
            dailyLimitCents: nil,
            suggestedModel: "haiku",
            description: "Bring-your-own"
        )
        _ = try await manager.saveCustom(custom)

        let all = try await manager.allPresets()

        XCTAssertEqual(all.count, BudgetPreset.builtin.count + 1)
        XCTAssertEqual(all.last?.id, "custom-tight")
        XCTAssertFalse(all.last?.isBuiltin ?? true,
                       "Custom presets are never marked built-in")
    }

    // MARK: - saveCustom

    func test_saveCustom_persistsToDisk() async throws {
        let manager = makeManager()
        let preset = BudgetPreset(
            id: "team-tight",
            name: "Team Tight",
            budgetCents: 2_000,
            warningPct: 70,
            hardStop: true,
            throttle: true,
            description: "Team-wide tight cap"
        )
        _ = try await manager.saveCustom(preset)

        // Restart manager — read from disk
        let manager2 = BudgetPresetManager(storeURL: await manager.storeURL)
        let restored = try await manager2.preset(withId: "team-tight")

        XCTAssertEqual(restored?.budgetCents, 2_000)
        XCTAssertEqual(restored?.name, "Team Tight")
        XCTAssertEqual(restored?.warningPct, 70)
    }

    func test_saveCustom_overwritesExistingId() async throws {
        let manager = makeManager()
        let v1 = BudgetPreset(
            id: "team-tight", name: "v1",
            budgetCents: 1_000, warningPct: 70,
            hardStop: true, throttle: true,
            description: "v1"
        )
        _ = try await manager.saveCustom(v1)

        let v2 = BudgetPreset(
            id: "team-tight", name: "v2",
            budgetCents: 4_200, warningPct: 90,
            hardStop: false, throttle: false,
            description: "v2"
        )
        _ = try await manager.saveCustom(v2)

        let custom = try await manager.customPresets()
        XCTAssertEqual(custom.count, 1, "Same id should not duplicate")
        XCTAssertEqual(custom.first?.budgetCents, 4_200)
        XCTAssertEqual(custom.first?.name, "v2")
    }

    func test_saveCustom_rejectsBuiltinId() async throws {
        let manager = makeManager()
        let collide = BudgetPreset(
            id: "frugal", name: "imposter",
            budgetCents: 999, warningPct: 50,
            hardStop: true, throttle: true,
            description: "shadow built-in"
        )

        do {
            _ = try await manager.saveCustom(collide)
            XCTFail("Expected builtinNotEditable")
        } catch let error as BudgetPresetError {
            switch error {
            case .builtinNotEditable(let id):
                XCTAssertEqual(id, "frugal")
            default:
                XCTFail("Wrong error: \(error)")
            }
        }

        // Built-in remains untouched
        let frugal = try await manager.preset(withId: "frugal")
        XCTAssertEqual(frugal?.budgetCents, BudgetPreset.frugal.budgetCents)
    }

    func test_saveCustom_validatesShape() async throws {
        let manager = makeManager()

        let badBudget = BudgetPreset(
            id: "bad-1", name: "bad",
            budgetCents: 0, warningPct: 80,
            hardStop: true, throttle: true,
            description: "zero budget"
        )
        await assertThrowsAsync(BudgetPresetError.self) {
            _ = try await manager.saveCustom(badBudget)
        }

        let badPct = BudgetPreset(
            id: "bad-2", name: "bad",
            budgetCents: 1_000, warningPct: 200,
            hardStop: true, throttle: true,
            description: "pct out of range"
        )
        await assertThrowsAsync(BudgetPresetError.self) {
            _ = try await manager.saveCustom(badPct)
        }

        let badName = BudgetPreset(
            id: "bad-3", name: "",
            budgetCents: 1_000, warningPct: 50,
            hardStop: true, throttle: true,
            description: "empty name"
        )
        await assertThrowsAsync(BudgetPresetError.self) {
            _ = try await manager.saveCustom(badName)
        }
    }

    func test_saveCustom_clearsBuiltinFlagOnInput() async throws {
        // Even if a caller passes isBuiltin=true on a non-reserved id,
        // the manager must persist it as non-builtin to keep the contract honest.
        let manager = makeManager()
        let preset = BudgetPreset(
            id: "sneaky",
            name: "Sneaky",
            budgetCents: 1_000,
            warningPct: 80,
            hardStop: true,
            throttle: true,
            description: "tries to claim builtin",
            isBuiltin: true
        )

        let saved = try await manager.saveCustom(preset)

        XCTAssertFalse(saved.isBuiltin)
        let restored = try await manager.preset(withId: "sneaky")
        XCTAssertFalse(restored?.isBuiltin ?? true)
    }

    // MARK: - deleteCustom

    func test_deleteCustom_removesPresetAndReturnsTrue() async throws {
        let manager = makeManager()
        let preset = BudgetPreset(
            id: "to-remove",
            name: "Remove Me",
            budgetCents: 800,
            warningPct: 60,
            hardStop: true, throttle: true,
            description: ""
        )
        _ = try await manager.saveCustom(preset)

        let removed = try await manager.deleteCustom(id: "to-remove")
        XCTAssertTrue(removed)

        let after = try await manager.preset(withId: "to-remove")
        XCTAssertNil(after)
    }

    func test_deleteCustom_returnsFalseWhenAbsent() async throws {
        let manager = makeManager()
        let removed = try await manager.deleteCustom(id: "ghost")
        XCTAssertFalse(removed)
    }

    func test_deleteCustom_rejectsBuiltinId() async throws {
        let manager = makeManager()
        do {
            _ = try await manager.deleteCustom(id: "standard")
            XCTFail("Expected builtinNotEditable")
        } catch let error as BudgetPresetError {
            switch error {
            case .builtinNotEditable(let id):
                XCTAssertEqual(id, "standard")
            default:
                XCTFail("Wrong error: \(error)")
            }
        }
        // Verify standard still resolvable
        let standard = try await manager.preset(withId: "standard")
        XCTAssertNotNil(standard)
    }

    // MARK: - clearCustomPresets

    func test_clearCustomPresets_keepsBuiltins() async throws {
        let manager = makeManager()
        _ = try await manager.saveCustom(BudgetPreset(
            id: "x", name: "x",
            budgetCents: 1_000, warningPct: 50,
            hardStop: true, throttle: true,
            description: ""
        ))

        try await manager.clearCustomPresets()

        let all = try await manager.allPresets()
        XCTAssertEqual(all.map(\.id), BudgetPreset.builtin.map(\.id))
    }

    // MARK: - Materialize

    func test_materialize_mapsAllFieldsToBudgetConfig() {
        let sessionId = UUID()
        let slotId = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let config = BudgetPreset.frugal.materialize(
            sessionId: sessionId,
            slotId: slotId,
            now: now
        )

        XCTAssertEqual(config.sessionId, sessionId)
        XCTAssertEqual(config.slotId, slotId)
        XCTAssertEqual(config.budgetCents, BudgetPreset.frugal.budgetCents)
        XCTAssertEqual(config.warningThresholdPct, BudgetPreset.frugal.warningPct)
        XCTAssertEqual(config.hardStopEnabled, BudgetPreset.frugal.hardStop)
        XCTAssertEqual(config.throttleEnabled, BudgetPreset.frugal.throttle)
        XCTAssertEqual(config.dailyLimitCents, BudgetPreset.frugal.dailyLimitCents)
        XCTAssertNil(config.perStoryLimitCents)
        XCTAssertEqual(config.createdAt, now)
        XCTAssertEqual(config.updatedAt, now)
    }

    func test_materialize_sessionLevelWhenSlotNil() {
        let config = BudgetPreset.standard.materialize(sessionId: UUID(), slotId: nil)
        XCTAssertNil(config.slotId, "Session-level config must have nil slotId")
    }

    // MARK: - apply(presetId:)

    func test_apply_returnsMaterializedConfigForKnownPreset() async throws {
        let manager = makeManager()
        let sessionId = UUID()

        let config = try await manager.apply(presetId: "performance", sessionId: sessionId)

        XCTAssertEqual(config.sessionId, sessionId)
        XCTAssertEqual(config.budgetCents, BudgetPreset.performance.budgetCents)
        XCTAssertEqual(config.warningThresholdPct, BudgetPreset.performance.warningPct)
    }

    func test_apply_throwsForUnknownPresetId() async throws {
        let manager = makeManager()
        do {
            _ = try await manager.apply(presetId: "nonexistent", sessionId: UUID())
            XCTFail("Expected invalidPreset")
        } catch let error as BudgetPresetError {
            switch error {
            case .invalidPreset:
                break
            default:
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Disk format

    func test_storeFile_isValidJSON() async throws {
        let manager = makeManager()
        let storeURL = await manager.storeURL

        _ = try await manager.saveCustom(BudgetPreset(
            id: "json-shape",
            name: "JSON Shape",
            budgetCents: 1_234,
            warningPct: 75,
            hardStop: true,
            throttle: false,
            dailyLimitCents: 10_000,
            suggestedModel: "sonnet",
            description: "round-trip"
        ))

        // File exists, parses as JSON, contains an array of presets
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        let data = try Data(contentsOf: storeURL)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Store must be a top-level JSON array")
    }

    func test_corruptedStore_surfacesDecodeError() async throws {
        let storeURL = tmpDir.appendingPathComponent("budget-presets.json")
        try "not-valid-json".data(using: .utf8)!.write(to: storeURL)

        let manager = BudgetPresetManager(storeURL: storeURL)

        do {
            _ = try await manager.allPresets()
            XCTFail("Expected decodeFailed")
        } catch let error as BudgetPresetError {
            switch error {
            case .decodeFailed:
                break
            default:
                XCTFail("Wrong error: \(error)")
            }
        }
    }
}

// MARK: - Async XCTest helper

private func assertThrowsAsync<E: Error, R>(
    _ expectedType: E.Type,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ block: () async throws -> R
) async {
    do {
        _ = try await block()
        XCTFail("Expected throw of \(E.self)", file: file, line: line)
    } catch is E {
        // expected
    } catch {
        XCTFail("Expected \(E.self), got \(type(of: error)): \(error)",
                file: file, line: line)
    }
}
