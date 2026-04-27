import Foundation

// MARK: - BudgetPreset

/// A reusable budget profile that can be applied to a CockpitSession or AgentSlot
/// when activating a workspace.
///
/// Built-in presets (Frugal / Standard / Performance / Unlimited) ship with the app and
/// are immutable. Custom presets can be saved by the operator and persist as JSON in
/// `<projectPath>/.crossroads/budget-presets.json`.
///
/// PRD-S02 / US-006.
struct BudgetPreset: Codable, Hashable, Sendable, Identifiable {

    /// Stable slug used as primary identifier. Built-in ids are reserved
    /// (`frugal`, `standard`, `performance`, `unlimited`).
    var id: String

    /// Display name shown in the picker.
    var name: String

    /// Total session budget cap in cents.
    var budgetCents: Int

    /// Warning threshold as integer percentage (0–100).
    var warningPct: Int

    /// If true, slot is paused at 100% spend.
    var hardStop: Bool

    /// If true, throttle is engaged at warning threshold.
    var throttle: Bool

    /// Optional rolling-day spend ceiling in cents. `nil` = no daily cap.
    var dailyLimitCents: Int?

    /// Optional model the preset suggests Conductor route to. `nil` = no preference.
    /// Examples: "sonnet", "opus", "haiku".
    var suggestedModel: String?

    /// Short, human-readable rationale for the picker.
    var description: String

    /// Marks built-in presets — UI must refuse to edit/delete these and the
    /// PresetManager enforces the same invariant on disk.
    var isBuiltin: Bool

    init(
        id: String,
        name: String,
        budgetCents: Int,
        warningPct: Int,
        hardStop: Bool,
        throttle: Bool,
        dailyLimitCents: Int? = nil,
        suggestedModel: String? = nil,
        description: String,
        isBuiltin: Bool = false
    ) {
        self.id = id
        self.name = name
        self.budgetCents = budgetCents
        self.warningPct = warningPct
        self.hardStop = hardStop
        self.throttle = throttle
        self.dailyLimitCents = dailyLimitCents
        self.suggestedModel = suggestedModel
        self.description = description
        self.isBuiltin = isBuiltin
    }
}

// MARK: - Built-in presets

extension BudgetPreset {

    /// Conservative — Sonnet only, $5 cap, daily $10.
    static let frugal = BudgetPreset(
        id: "frugal",
        name: "Frugal",
        budgetCents: 500,
        warningPct: 70,
        hardStop: true,
        throttle: true,
        dailyLimitCents: 1_000,
        suggestedModel: "sonnet",
        description: "Sonnet-only, $5 session cap, hard stop.",
        isBuiltin: true
    )

    /// Default — mixed models, $25 cap, daily $50.
    static let standard = BudgetPreset(
        id: "standard",
        name: "Standard",
        budgetCents: 2_500,
        warningPct: 80,
        hardStop: true,
        throttle: true,
        dailyLimitCents: 5_000,
        suggestedModel: nil,
        description: "Mixed models, $25 session cap.",
        isBuiltin: true
    )

    /// Heavy lifting — Opus allowed, $100 cap, daily $250.
    static let performance = BudgetPreset(
        id: "performance",
        name: "Performance",
        budgetCents: 10_000,
        warningPct: 85,
        hardStop: true,
        throttle: false,
        dailyLimitCents: 25_000,
        suggestedModel: "opus",
        description: "Opus-allowed, $100 session cap.",
        isBuiltin: true
    )

    /// No caps — observation/monitoring only. Use with care.
    static let unlimited = BudgetPreset(
        id: "unlimited",
        name: "Unlimited",
        // Sentinel large value rather than Int.max to avoid overflow
        // when callers do arithmetic against `budgetCents`.
        budgetCents: 1_000_000_000,
        warningPct: 90,
        hardStop: false,
        throttle: false,
        dailyLimitCents: nil,
        suggestedModel: nil,
        description: "Monitoring only — no caps. Operator-verified spend.",
        isBuiltin: true
    )

    /// All built-in presets in display order.
    static let builtin: [BudgetPreset] = [.frugal, .standard, .performance, .unlimited]

    /// Reserved built-in ids — custom presets cannot reuse these.
    static let reservedIds: Set<String> = Set(builtin.map(\.id))
}

// MARK: - Materialization

extension BudgetPreset {

    /// Materializes this preset into a concrete `BudgetConfig` for a session
    /// (and optionally a single slot).
    ///
    /// - Parameters:
    ///   - sessionId: Owning cockpit session.
    ///   - slotId: Optional slot scope. When `nil`, the config is session-level.
    ///   - now: Injection point for tests.
    /// - Returns: An unsaved `BudgetConfig` ready for persistence.
    func materialize(
        sessionId: UUID,
        slotId: UUID? = nil,
        now: Date = Date()
    ) -> BudgetConfig {
        BudgetConfig(
            sessionId: sessionId,
            slotId: slotId,
            budgetCents: budgetCents,
            warningThresholdPct: warningPct,
            hardStopEnabled: hardStop,
            throttleEnabled: throttle,
            dailyLimitCents: dailyLimitCents,
            perStoryLimitCents: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
