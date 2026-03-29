import Foundation
import os

// MARK: - HeartbeatError

enum HeartbeatError: LocalizedError, Sendable {
    case invalidCronExpression(String)
    case cronFieldOutOfRange(field: String, value: Int, range: ClosedRange<Int>)

    var errorDescription: String? {
        switch self {
        case .invalidCronExpression(let expr):
            return "Invalid cron expression: '\(expr)'. Expected 5 space-separated fields."
        case .cronFieldOutOfRange(let field, let value, let range):
            return "Cron field '\(field)' value \(value) out of range \(range)"
        }
    }
}

// MARK: - PulseResult

/// Result of a heartbeat pulse check on an agent slot's worktree.
struct PulseResult: Codable, Sendable {
    /// Whether the agent process is still running
    let alive: Bool
    /// Number of uncommitted git changes (files modified/added/deleted)
    let gitChanges: Int
    /// Number of tests that passed in latest output
    let testsPassed: Int
    /// Number of tests that failed in latest output
    let testsFailed: Int
    /// Number of stories marked complete in prd.json
    let storiesCompleted: Int
    /// Whether the worktree branch is mergeable (no conflicts)
    let mergeable: Bool
    /// Errors encountered during the pulse check
    let errors: [String]
}

// MARK: - HeartbeatService

/// Monitors agent slot health via periodic pulse checks.
///
/// Inspects worktree state (git changes, test results, story progress)
/// and supports cron-based scheduling for automated runs.
actor HeartbeatService {

    private let logger = Logger(subsystem: "com.xroads", category: "Heartbeat")
    private let heartbeatRepository: HeartbeatRepository

    init(heartbeatRepository: HeartbeatRepository) {
        self.heartbeatRepository = heartbeatRepository
    }

    // MARK: - Pulse Check

    /// Creates a pulse result by inspecting the worktree state for an agent slot.
    ///
    /// Checks:
    /// - Process alive (via pid file or process table)
    /// - Git diff stat for uncommitted changes
    /// - Test output in recent logs
    /// - PRD story completion status
    /// - Branch mergeability
    ///
    /// - Parameters:
    ///   - slotId: The agent slot being monitored
    ///   - worktreePath: Filesystem path to the agent's worktree
    /// - Returns: PulseResult with all health metrics
    func createPulseResult(slotId: UUID, worktreePath: String) -> PulseResult {
        var errors: [String] = []

        // Check process alive via pid file
        let alive = checkProcessAlive(worktreePath: worktreePath)

        // Count git changes
        let gitChanges = countGitChanges(worktreePath: worktreePath, errors: &errors)

        // Parse test results from logs
        let (testsPassed, testsFailed) = parseTestResults(worktreePath: worktreePath, errors: &errors)

        // Count completed stories from prd.json
        let storiesCompleted = countCompletedStories(worktreePath: worktreePath, errors: &errors)

        // Check if branch is mergeable
        let mergeable = checkMergeable(worktreePath: worktreePath, errors: &errors)

        let result = PulseResult(
            alive: alive,
            gitChanges: gitChanges,
            testsPassed: testsPassed,
            testsFailed: testsFailed,
            storiesCompleted: storiesCompleted,
            mergeable: mergeable,
            errors: errors
        )

        logger.info("Pulse slot \(slotId): alive=\(alive), changes=\(gitChanges), tests=\(testsPassed)/\(testsPassed + testsFailed), stories=\(storiesCompleted)")

        return result
    }

    // MARK: - Cron Parsing

    /// Parses a standard 5-field cron expression and returns the next execution time.
    ///
    /// Fields: minute hour dayOfMonth month dayOfWeek
    /// Supports: specific values, wildcards (*), ranges (1-5), steps (*/15), lists (1,3,5)
    ///
    /// - Parameter expression: Standard 5-field cron expression (e.g., "*/30 * * * *")
    /// - Returns: The next Date when this cron expression triggers
    func parseCron(expression: String) throws -> Date {
        let fields = expression.trimmingCharacters(in: .whitespaces).split(separator: " ")

        guard fields.count == 5 else {
            throw HeartbeatError.invalidCronExpression(expression)
        }

        let minuteValues = try parseCronField(String(fields[0]), name: "minute", range: 0...59)
        let hourValues = try parseCronField(String(fields[1]), name: "hour", range: 0...23)
        let domValues = try parseCronField(String(fields[2]), name: "dayOfMonth", range: 1...31)
        let monthValues = try parseCronField(String(fields[3]), name: "month", range: 1...12)
        let dowValues = try parseCronField(String(fields[4]), name: "dayOfWeek", range: 0...6)

        // Find the next matching date from now
        let calendar = Calendar.current
        let now = Date()
        var candidate = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)

        // Advance by one minute to ensure we always return a future time
        candidate.minute = (candidate.minute ?? 0) + 1
        guard var searchDate = calendar.date(from: candidate) else {
            throw HeartbeatError.invalidCronExpression(expression)
        }

        // Search up to 366 days ahead (covers all cron patterns including yearly)
        let maxIterations = 366 * 24 * 60  // one year in minutes
        for _ in 0..<maxIterations {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: searchDate)

            let minute = components.minute ?? 0
            let hour = components.hour ?? 0
            let day = components.day ?? 1
            let month = components.month ?? 1
            // Calendar weekday: 1=Sunday, convert to cron: 0=Sunday
            let weekday = (components.weekday ?? 1) - 1

            if minuteValues.contains(minute)
                && hourValues.contains(hour)
                && domValues.contains(day)
                && monthValues.contains(month)
                && dowValues.contains(weekday) {
                return searchDate
            }

            // Advance by one minute
            searchDate = searchDate.addingTimeInterval(60)
        }

        // Should not reach here for valid expressions
        throw HeartbeatError.invalidCronExpression(expression)
    }

    // MARK: - Scheduled Runs

    /// Fetches all scheduled runs that are due for execution.
    ///
    /// A run is due if it is enabled, has a nextRunAt in the past or now,
    /// and its cron expression matches.
    ///
    /// - Returns: Array of ScheduledRun records that should be executed
    func checkScheduledRuns() async throws -> [ScheduledRun] {
        let allRuns = try await heartbeatRepository.fetchEnabledScheduledRuns()
        let now = Date()

        var dueRuns: [ScheduledRun] = []

        for run in allRuns {
            // Check if nextRunAt is in the past or now
            if let nextRunAt = run.nextRunAt, nextRunAt <= now {
                dueRuns.append(run)
                continue
            }

            // If no nextRunAt but has a cron expression, compute it
            if run.nextRunAt == nil, let cronExpr = run.cronExpression {
                do {
                    let nextDate = try parseCron(expression: cronExpr)
                    if nextDate <= now {
                        dueRuns.append(run)
                    }
                } catch {
                    logger.warning("Invalid cron for run \(run.id): \(error.localizedDescription)")
                }
            }
        }

        if !dueRuns.isEmpty {
            logger.info("Found \(dueRuns.count) scheduled runs due for execution")
        }

        return dueRuns
    }

    // MARK: - Private Helpers

    /// Checks if the agent process is alive by looking for a .pid file in the worktree.
    private func checkProcessAlive(worktreePath: String) -> Bool {
        let pidPath = (worktreePath as NSString).appendingPathComponent(".xroads-agent.pid")

        guard let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString) else {
            return false
        }

        // kill with signal 0 checks if process exists without sending a signal
        return kill(pid, 0) == 0
    }

    /// Counts uncommitted git changes in the worktree.
    private func countGitChanges(worktreePath: String, errors: inout [String]) -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", worktreePath, "status", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
            return lines.count
        } catch {
            errors.append("git status failed: \(error.localizedDescription)")
            return 0
        }
    }

    /// Parses test results from the latest log file in the worktree.
    private func parseTestResults(worktreePath: String, errors: inout [String]) -> (passed: Int, failed: Int) {
        let logPath = (worktreePath as NSString).appendingPathComponent(".xroads-agent.log")

        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            // No log file is normal for new slots
            return (0, 0)
        }

        // Look for common test output patterns in the last 200 lines
        let lines = content.split(separator: "\n").suffix(200)
        var passed = 0
        var failed = 0

        for line in lines {
            let lower = line.lowercased()

            // Swift test output: "Test Suite 'All tests' passed at..."
            // Generic: "X passed", "X failed"
            if lower.contains("passed") {
                if let match = extractTestCount(from: String(line), keyword: "passed") {
                    passed += match
                }
            }
            if lower.contains("failed") {
                if let match = extractTestCount(from: String(line), keyword: "failed") {
                    failed += match
                }
            }
        }

        return (passed, failed)
    }

    /// Extracts a numeric count before a keyword (e.g., "42 passed" -> 42).
    private func extractTestCount(from line: String, keyword: String) -> Int? {
        let components = line.lowercased().components(separatedBy: keyword)
        guard let before = components.first else { return nil }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let tokens = trimmed.split(separator: " ")
        guard let lastToken = tokens.last, let count = Int(lastToken) else { return nil }
        return count
    }

    /// Counts completed stories from prd.json in the worktree.
    private func countCompletedStories(worktreePath: String, errors: inout [String]) -> Int {
        let prdPath = (worktreePath as NSString).appendingPathComponent("prd.json")

        guard let data = FileManager.default.contents(atPath: prdPath) else {
            return 0
        }

        // Parse prd.json looking for stories with status "done" or "completed"
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stories = json["stories"] as? [[String: Any]] else {
                return 0
            }

            return stories.filter { story in
                guard let status = story["status"] as? String else { return false }
                return status == "done" || status == "completed"
            }.count
        } catch {
            errors.append("prd.json parse error: \(error.localizedDescription)")
            return 0
        }
    }

    /// Checks if the worktree branch has merge conflicts with main.
    private func checkMergeable(worktreePath: String, errors: inout [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", worktreePath, "diff", "--check", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            // Exit code 0 means no conflict markers
            return process.terminationStatus == 0
        } catch {
            errors.append("git diff --check failed: \(error.localizedDescription)")
            return true  // Assume mergeable if check fails
        }
    }

    /// Parses a single cron field into a set of matching values.
    private func parseCronField(_ field: String, name: String, range: ClosedRange<Int>) throws -> Set<Int> {
        var values = Set<Int>()

        let parts = field.split(separator: ",")
        for part in parts {
            let token = String(part)

            if token == "*" {
                // Wildcard: all values in range
                values.formUnion(range)
            } else if token.contains("/") {
                // Step: */N or M/N
                let stepParts = token.split(separator: "/")
                guard stepParts.count == 2, let step = Int(stepParts[1]), step > 0 else {
                    throw HeartbeatError.invalidCronExpression("Bad step in field '\(name)': \(token)")
                }
                let base: Int
                if stepParts[0] == "*" {
                    base = range.lowerBound
                } else if let b = Int(stepParts[0]) {
                    base = b
                } else {
                    throw HeartbeatError.invalidCronExpression("Bad base in field '\(name)': \(token)")
                }
                var current = base
                while current <= range.upperBound {
                    values.insert(current)
                    current += step
                }
            } else if token.contains("-") {
                // Range: M-N
                let rangeParts = token.split(separator: "-")
                guard rangeParts.count == 2,
                      let low = Int(rangeParts[0]),
                      let high = Int(rangeParts[1]),
                      low <= high else {
                    throw HeartbeatError.invalidCronExpression("Bad range in field '\(name)': \(token)")
                }
                guard range.contains(low), range.contains(high) else {
                    throw HeartbeatError.cronFieldOutOfRange(field: name, value: low < range.lowerBound ? low : high, range: range)
                }
                values.formUnion(low...high)
            } else if let value = Int(token) {
                // Single value
                guard range.contains(value) else {
                    throw HeartbeatError.cronFieldOutOfRange(field: name, value: value, range: range)
                }
                values.insert(value)
            } else {
                throw HeartbeatError.invalidCronExpression("Unparseable field '\(name)': \(token)")
            }
        }

        return values
    }
}
