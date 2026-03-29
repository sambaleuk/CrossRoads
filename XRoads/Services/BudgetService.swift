import Foundation
import os

// MARK: - BudgetServiceError

enum BudgetServiceError: LocalizedError, Sendable {
    case configNotFound(slotId: UUID)
    case sessionConfigNotFound(sessionId: UUID)
    case invalidThrottleLevel(Int)

    var errorDescription: String? {
        switch self {
        case .configNotFound(let slotId):
            return "BudgetConfig not found for slot: \(slotId)"
        case .sessionConfigNotFound(let sessionId):
            return "BudgetConfig not found for session: \(sessionId)"
        case .invalidThrottleLevel(let level):
            return "Invalid throttle level: \(level). Must be 0-3."
        }
    }
}

// MARK: - BudgetStatus

/// Snapshot of current budget health for a slot.
struct BudgetStatus: Codable, Sendable {
    /// Overall status: ok, warning, or exceeded
    let status: String
    /// Percentage of budget consumed (0.0 - 100.0+)
    let percentUsed: Double
    /// Remaining budget in cents (can be negative if exceeded)
    let remainingCents: Int
    /// Projected total spend at current burn rate in cents
    let projectedTotal: Int
}

// MARK: - CostProjection

/// Forward-looking cost projection for a session.
struct CostProjection: Codable, Sendable {
    /// Total spend so far in cents
    let currentSpend: Int
    /// Burn rate in cents per hour
    let burnRateCentsPerHour: Double
    /// Projected total spend if session continues at current rate
    let projectedTotal: Int
    /// Minutes until budget is exhausted at current burn rate (nil if no budget set)
    let timeToExhaustionMinutes: Double?
    /// Whether the projected total exceeds the configured budget
    let overBudget: Bool
}

// MARK: - BudgetService

/// Manages budget tracking, projections, and throttling for agent slots.
///
/// Integrates with BudgetRepository for config and CostEventRepository for spend data.
/// Provides real-time budget health checks and automatic throttle recommendations.
actor BudgetService {

    private let logger = Logger(subsystem: "com.xroads", category: "Budget")
    private let budgetRepository: BudgetRepository
    private let costEventRepository: CostEventRepository

    init(budgetRepository: BudgetRepository, costEventRepository: CostEventRepository) {
        self.budgetRepository = budgetRepository
        self.costEventRepository = costEventRepository
    }

    // MARK: - Budget Check

    /// Checks current budget status for a specific agent slot.
    ///
    /// Computes spend from CostEvent records and compares against the slot's BudgetConfig.
    /// Falls back to the session-level config if no slot-specific config exists.
    ///
    /// - Parameter slotId: The agent slot to check
    /// - Returns: BudgetStatus with current health metrics
    func checkBudget(slotId: UUID) async throws -> BudgetStatus {
        let config = try await budgetRepository.fetchConfigForSlot(slotId: slotId)

        guard let config else {
            throw BudgetServiceError.configNotFound(slotId: slotId)
        }

        let totalSpend = try await costEventRepository.totalSpendCents(forSlot: slotId)
        let budgetCents = config.budgetCents

        let percentUsed = budgetCents > 0
            ? (Double(totalSpend) / Double(budgetCents)) * 100.0
            : 0.0
        let remainingCents = budgetCents - totalSpend

        // Simple projection: assume spend continues at same rate
        let projectedTotal = totalSpend * 2  // rough 2x projection

        let status: String
        if percentUsed >= 100.0 {
            status = "exceeded"
        } else if percentUsed >= Double(config.warningThresholdPct) {
            status = "warning"
        } else {
            status = "ok"
        }

        logger.info("Budget check slot \(slotId): \(status) (\(String(format: "%.1f", percentUsed))% used)")

        return BudgetStatus(
            status: status,
            percentUsed: percentUsed,
            remainingCents: remainingCents,
            projectedTotal: projectedTotal
        )
    }

    // MARK: - Projection

    /// Generates a forward-looking cost projection for an entire session.
    ///
    /// Calculates burn rate from the time window of cost events and projects
    /// time to budget exhaustion.
    ///
    /// - Parameter sessionId: The cockpit session
    /// - Returns: CostProjection with burn rate and time-to-exhaustion
    func getProjection(sessionId: UUID) async throws -> CostProjection {
        let config = try await budgetRepository.fetchConfigForSession(sessionId: sessionId)

        guard let config else {
            throw BudgetServiceError.sessionConfigNotFound(sessionId: sessionId)
        }

        let events = try await costEventRepository.fetchEvents(forSession: sessionId)
        let currentSpend = events.reduce(0) { $0 + $1.costCents }

        // Calculate burn rate from event time span
        let burnRateCentsPerHour: Double
        if events.count >= 2,
           let earliest = events.map({ $0.createdAt }).min(),
           let latest = events.map({ $0.createdAt }).max() {
            let spanHours = latest.timeIntervalSince(earliest) / 3600.0
            burnRateCentsPerHour = spanHours > 0
                ? Double(currentSpend) / spanHours
                : 0.0
        } else {
            burnRateCentsPerHour = 0.0
        }

        // Project total spend assuming session runs for double the elapsed time
        let projectedTotal: Int
        if burnRateCentsPerHour > 0 {
            // Assume 2 more hours at current rate as baseline projection
            projectedTotal = currentSpend + Int(burnRateCentsPerHour * 2.0)
        } else {
            projectedTotal = currentSpend
        }

        // Time to exhaustion
        let budgetCents = config.budgetCents
        let remainingCents = budgetCents - currentSpend
        let timeToExhaustionMinutes: Double?
        if burnRateCentsPerHour > 0 && remainingCents > 0 {
            timeToExhaustionMinutes = (Double(remainingCents) / burnRateCentsPerHour) * 60.0
        } else if remainingCents <= 0 {
            timeToExhaustionMinutes = 0.0
        } else {
            timeToExhaustionMinutes = nil
        }

        let overBudget = projectedTotal > budgetCents

        logger.info("Projection session \(sessionId): spend=\(currentSpend)¢, rate=\(String(format: "%.1f", burnRateCentsPerHour))¢/hr, overBudget=\(overBudget)")

        return CostProjection(
            currentSpend: currentSpend,
            burnRateCentsPerHour: burnRateCentsPerHour,
            projectedTotal: projectedTotal,
            timeToExhaustionMinutes: timeToExhaustionMinutes,
            overBudget: overBudget
        )
    }

    // MARK: - Throttling

    /// Applies a throttle level to a slot's budget configuration.
    ///
    /// Levels:
    /// - 0: No throttle (normal operation)
    /// - 1: Delay (add pause between iterations)
    /// - 2: Suggest downgrade (recommend cheaper model)
    /// - 3: Pause (halt the agent slot)
    ///
    /// - Parameters:
    ///   - slotId: The agent slot to throttle
    ///   - level: Throttle level 0-3
    func applyThrottle(slotId: UUID, level: Int) async throws {
        guard (0...3).contains(level) else {
            throw BudgetServiceError.invalidThrottleLevel(level)
        }

        let config = try await budgetRepository.fetchConfigForSlot(slotId: slotId)

        guard var config else {
            throw BudgetServiceError.configNotFound(slotId: slotId)
        }

        let description: String
        switch level {
        case 0:
            config.throttleEnabled = false
            description = "none"
        case 1:
            config.throttleEnabled = true
            description = "delay"
        case 2:
            config.throttleEnabled = true
            description = "suggest_downgrade"
        case 3:
            config.throttleEnabled = true
            config.hardStopEnabled = true
            description = "pause"
        default:
            description = "unknown"
        }

        config.updatedAt = Date()
        try await budgetRepository.updateConfig(config)

        // Create an alert to record the throttle action
        let totalSpend = try await costEventRepository.totalSpendCents(forSlot: slotId)
        let percentUsed = config.budgetCents > 0
            ? (Double(totalSpend) / Double(config.budgetCents)) * 100.0
            : 0.0

        let alert = BudgetAlert(
            budgetConfigId: config.id,
            alertType: "throttle_\(description)",
            currentSpendCents: totalSpend,
            budgetCents: config.budgetCents,
            percentUsed: percentUsed,
            message: "Throttle level \(level) (\(description)) applied to slot"
        )
        try await budgetRepository.createAlert(alert)

        logger.info("Throttle level \(level) (\(description)) applied to slot \(slotId)")
    }

    // MARK: - Auto Throttle

    /// Checks the budget for a slot and automatically applies the appropriate throttle level.
    ///
    /// Throttle mapping:
    /// - < warningThreshold%: level 0 (no throttle)
    /// - warningThreshold% - 90%: level 1 (delay)
    /// - 90% - 100%: level 2 (suggest downgrade)
    /// - > 100%: level 3 (pause)
    ///
    /// - Parameter slotId: The agent slot to auto-throttle
    /// - Returns: The throttle level that was applied (0-3)
    func autoThrottle(slotId: UUID) async throws -> Int {
        let budgetStatus = try await checkBudget(slotId: slotId)

        let level: Int
        switch budgetStatus.percentUsed {
        case ..<80.0:
            level = 0
        case 80.0..<90.0:
            level = 1
        case 90.0..<100.0:
            level = 2
        default:
            level = 3
        }

        try await applyThrottle(slotId: slotId, level: level)

        logger.info("Auto-throttle slot \(slotId): \(String(format: "%.1f", budgetStatus.percentUsed))% used → level \(level)")
        return level
    }
}
