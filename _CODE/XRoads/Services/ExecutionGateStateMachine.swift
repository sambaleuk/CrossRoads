import Foundation

// MARK: - ExecutionGateEvent

/// Events that drive ExecutionGateLifecycle transitions (from states.json)
enum ExecutionGateEvent: String, Sendable {
    case policyAllow = "policy_allow"
    case policyDeny = "policy_deny"
    case policyDirect = "policy_direct"
    case dryRunDone = "dry_run_done"
    case dryRunFail = "dry_run_fail"
    case approve
    case reject
    case success
    case anomaly
}

// MARK: - ExecutionGateStateMachineError

enum ExecutionGateStateMachineError: LocalizedError, Equatable {
    case invalidTransition(from: ExecutionGateStatus, event: ExecutionGateEvent)
    case guardViolation(guard: String, event: ExecutionGateEvent)

    var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let event):
            return "Invalid transition: cannot apply '\(event.rawValue)' from state '\(from.rawValue)'"
        case .guardViolation(let guardName, let event):
            return "Guard violation: '\(guardName)' failed for event '\(event.rawValue)'"
        }
    }
}

// MARK: - GuardContext

/// Context passed to guard evaluation for ExecutionGateLifecycle transitions
struct ExecutionGateGuardContext: Sendable {
    let requiresDryRun: Bool
    let riskIsLow: Bool
    let dryRunFeasible: Bool
    let approvedByHuman: Bool

    init(
        requiresDryRun: Bool = false,
        riskIsLow: Bool = false,
        dryRunFeasible: Bool = false,
        approvedByHuman: Bool = false
    ) {
        self.requiresDryRun = requiresDryRun
        self.riskIsLow = riskIsLow
        self.dryRunFeasible = dryRunFeasible
        self.approvedByHuman = approvedByHuman
    }
}

// MARK: - ExecutionGateStateMachine

/// Enforces ExecutionGateLifecycle transitions strictly per states.json.
/// No direct status override — all transitions go through this machine.
enum ExecutionGateStateMachine {

    /// Apply an event to the current status, returning the new status.
    /// Throws if the transition is invalid or a guard fails.
    static func transition(
        from current: ExecutionGateStatus,
        event: ExecutionGateEvent,
        context: ExecutionGateGuardContext = ExecutionGateGuardContext()
    ) throws -> ExecutionGateStatus {
        switch (current, event) {

        // pending -> dry_run (guard: requires_dry_run)
        case (.pending, .policyAllow):
            guard context.requiresDryRun else {
                throw ExecutionGateStateMachineError.guardViolation(
                    guard: "requires_dry_run", event: event
                )
            }
            return .dryRun

        // pending -> rejected
        case (.pending, .policyDeny):
            return .rejected

        // pending -> executing (guard: risk_is_low)
        case (.pending, .policyDirect):
            guard context.riskIsLow else {
                throw ExecutionGateStateMachineError.guardViolation(
                    guard: "risk_is_low", event: event
                )
            }
            return .executing

        // dry_run -> awaiting_approval (guard: dry_run_feasible)
        case (.dryRun, .dryRunDone):
            guard context.dryRunFeasible else {
                throw ExecutionGateStateMachineError.guardViolation(
                    guard: "dry_run_feasible", event: event
                )
            }
            return .awaitingApproval

        // dry_run -> rejected
        case (.dryRun, .dryRunFail):
            return .rejected

        // awaiting_approval -> executing (guard: approved_by_human)
        case (.awaitingApproval, .approve):
            guard context.approvedByHuman else {
                throw ExecutionGateStateMachineError.guardViolation(
                    guard: "approved_by_human", event: event
                )
            }
            return .executing

        // awaiting_approval -> rejected
        case (.awaitingApproval, .reject):
            return .rejected

        // executing -> completed
        case (.executing, .success):
            return .completed

        // executing -> rolled_back
        case (.executing, .anomaly):
            return .rolledBack

        default:
            throw ExecutionGateStateMachineError.invalidTransition(from: current, event: event)
        }
    }
}
