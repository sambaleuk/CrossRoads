import Foundation
import os

// MARK: - BudgetPresetError

enum BudgetPresetError: LocalizedError, Sendable {
    case builtinNotEditable(String)
    case duplicateId(String)
    case invalidPreset(reason: String)
    case decodeFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .builtinNotEditable(let id):
            return "Built-in preset '\(id)' cannot be modified or deleted"
        case .duplicateId(let id):
            return "A custom preset with id '\(id)' already exists"
        case .invalidPreset(let reason):
            return "Invalid preset: \(reason)"
        case .decodeFailed(let underlying):
            return "Failed to decode budget-presets.json: \(underlying)"
        }
    }
}

// MARK: - BudgetPresetManager

/// Read/write store for `BudgetPreset` records.
///
/// Built-in presets (Frugal / Standard / Performance / Unlimited) are immutable and
/// always returned by `allPresets()`. Custom presets persist to disk at
/// `<storeURL>` (default: `<projectPath>/.crossroads/budget-presets.json`).
///
/// PRD-S02 / US-006.
actor BudgetPresetManager {

    private let logger = Logger(subsystem: "com.xroads", category: "BudgetPreset")
    private let fileManager: FileManager
    let storeURL: URL

    // MARK: Init

    init(storeURL: URL, fileManager: FileManager = .default) {
        self.storeURL = storeURL
        self.fileManager = fileManager
    }

    /// Default store URL: `<projectPath>/.crossroads/budget-presets.json`.
    static func defaultStoreURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".crossroads", isDirectory: true)
            .appendingPathComponent("budget-presets.json", isDirectory: false)
    }

    // MARK: - Public API

    /// Returns built-in presets followed by user-defined custom presets.
    func allPresets() throws -> [BudgetPreset] {
        let custom = try loadCustom()
        return BudgetPreset.builtin + custom
    }

    /// Returns the preset with the given id, or nil if no match.
    func preset(withId id: String) throws -> BudgetPreset? {
        try allPresets().first { $0.id == id }
    }

    /// Returns only the custom (user-defined) presets currently on disk.
    func customPresets() throws -> [BudgetPreset] {
        try loadCustom()
    }

    /// Saves a custom preset. If a custom preset with the same id already exists,
    /// it is replaced. Built-in ids are rejected.
    @discardableResult
    func saveCustom(_ preset: BudgetPreset) throws -> BudgetPreset {
        try validate(preset)
        guard !BudgetPreset.reservedIds.contains(preset.id) else {
            throw BudgetPresetError.builtinNotEditable(preset.id)
        }

        var stored = preset
        stored.isBuiltin = false  // can never be saved as built-in

        var custom = try loadCustom()
        custom.removeAll { $0.id == stored.id }
        custom.append(stored)
        try writeCustom(custom)
        logger.info("Saved custom preset \(stored.id, privacy: .public)")
        return stored
    }

    /// Deletes a custom preset by id. Built-in presets cannot be deleted.
    /// Returns true if a preset was actually removed.
    @discardableResult
    func deleteCustom(id: String) throws -> Bool {
        guard !BudgetPreset.reservedIds.contains(id) else {
            throw BudgetPresetError.builtinNotEditable(id)
        }
        var custom = try loadCustom()
        let originalCount = custom.count
        custom.removeAll { $0.id == id }
        let removed = custom.count != originalCount
        if removed {
            try writeCustom(custom)
            logger.info("Deleted custom preset \(id, privacy: .public)")
        }
        return removed
    }

    /// Removes all custom presets but preserves built-ins.
    /// Useful when an operator wants to reset their workspace.
    func clearCustomPresets() throws {
        try writeCustom([])
        logger.info("Cleared all custom presets")
    }

    /// Convenience: applies a preset to a session by materializing it into a
    /// `BudgetConfig`. Caller is responsible for persisting via `BudgetRepository`.
    func apply(
        presetId: String,
        sessionId: UUID,
        slotId: UUID? = nil,
        now: Date = Date()
    ) throws -> BudgetConfig {
        guard let preset = try preset(withId: presetId) else {
            throw BudgetPresetError.invalidPreset(reason: "preset id '\(presetId)' not found")
        }
        return preset.materialize(sessionId: sessionId, slotId: slotId, now: now)
    }

    // MARK: - Validation

    private func validate(_ preset: BudgetPreset) throws {
        guard !preset.id.isEmpty else {
            throw BudgetPresetError.invalidPreset(reason: "id must not be empty")
        }
        guard !preset.name.isEmpty else {
            throw BudgetPresetError.invalidPreset(reason: "name must not be empty")
        }
        guard preset.budgetCents > 0 else {
            throw BudgetPresetError.invalidPreset(reason: "budgetCents must be > 0")
        }
        guard (1...100).contains(preset.warningPct) else {
            throw BudgetPresetError.invalidPreset(reason: "warningPct must be 1–100")
        }
        if let daily = preset.dailyLimitCents {
            guard daily > 0 else {
                throw BudgetPresetError.invalidPreset(reason: "dailyLimitCents must be > 0 when set")
            }
        }
    }

    // MARK: - Disk I/O

    private func loadCustom() throws -> [BudgetPreset] {
        guard fileManager.fileExists(atPath: storeURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: storeURL)
        } catch {
            throw BudgetPresetError.decodeFailed(underlying: error.localizedDescription)
        }
        guard !data.isEmpty else { return [] }
        do {
            let decoded = try JSONDecoder().decode([BudgetPreset].self, from: data)
            // Strip any rogue records that try to claim built-in identity.
            return decoded
                .filter { !BudgetPreset.reservedIds.contains($0.id) }
                .map { var p = $0; p.isBuiltin = false; return p }
        } catch {
            throw BudgetPresetError.decodeFailed(underlying: error.localizedDescription)
        }
    }

    private func writeCustom(_ presets: [BudgetPreset]) throws {
        let dir = storeURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(presets)
        try data.write(to: storeURL, options: .atomic)
    }
}
