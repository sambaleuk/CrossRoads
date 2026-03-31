import Foundation
import os

// MARK: - ClaudeChairmanClient

/// Chairman implementation powered by Claude Code.
///
/// Instead of hardcoded Swift logic (DemoCockpitCouncilClient) or Python subprocess
/// (CockpitCouncilClient), this client runs a one-shot Claude Code session to
/// deliberate on slot assignments. The cockpit brain IS the chairman — it analyzes
/// the project context with full AI reasoning and produces the strategy.
///
/// The same soul.md that powers the cockpit brain also informs the chairman's
/// deliberation, ensuring continuity of identity between planning and monitoring.
final class ClaudeChairmanClient: CockpitCouncilClientProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.xroads", category: "ClaudeChairman")

    func deliberate(input: ChairmanInput) async throws -> ChairmanOutput {
        let projectName = (input.projectPath as NSString).lastPathComponent

        // Build context for Claude
        let branchList = input.openBranches.prefix(10).joined(separator: "\n  - ")
        let commitSummary = input.gitLog.prefix(15).map { "  - \($0.shortSha) \($0.message) (\($0.author))" }.joined(separator: "\n")

        var prdSection = "No active PRD."
        if let prd = input.prdSummary {
            prdSection = """
            PRD: \(prd.featureName)
            Status: \(prd.status)
            Stories: \(prd.totalStories) total, \(prd.pendingStories) pending, \(prd.completedStories) completed
            """
        }

        let prompt = """
        You are the Chairman of XRoads, a multi-agent AI coding orchestrator.
        Your job: analyze this project and decide how to distribute work across 3 parallel agent slots.

        ## Project: \(projectName)
        Path: \(input.projectPath)

        ## Git Branches
          - \(branchList.isEmpty ? "main" : branchList)

        ## Recent Commits
        \(commitSummary.isEmpty ? "  (no commits yet)" : commitSummary)

        ## PRD
        \(prdSection)

        ## Available Agents
        - **claude** — Best for complex logic, architecture, debugging. Most expensive.
        - **gemini** — Good for testing, code review, boilerplate. Cost-effective.
        - **codex** — Good for straightforward implementations. Fast.

        ## Slot Roles (skillName)
        Each slot has a ROLE, not just a code domain. Choose from:

        | skillName | Action Type | Skills Loaded | Best Agent | Purpose |
        |-----------|------------|---------------|------------|---------|
        | `backend` | implement | prd, code-writer, commit | claude | Core logic, APIs, services |
        | `frontend` | implement | prd, code-writer, commit | claude | UI, components, user flows |
        | `testing` | integrationTest | integration-test, e2e-test, perf-test | gemini | E2E and integration tests |
        | `review` | review | code-reviewer, lint | claude | Deep code review, OWASP, SOLID |
        | `docs` | write | doc-generator | claude/gemini | README, API docs, guides |
        | `security` | review | code-reviewer | claude | Security audit, compliance |
        | `debug` | debug | bug-reproducer, code-reviewer, commit | claude | Bug reproduction and fix |
        | `devops` | custom | (custom) | claude | CI/CD, infrastructure, deployment |
        | `general` | implement | prd, code-writer, commit | claude | General improvements |

        Think in PHASES: a session isn't "3 coders" — it's an orchestration.
        - BUILD phase: 2-3 implement slots + 1 docs slot
        - VERIFY phase: 1-2 review slots + 1 testing slot
        - DELIVER phase: 1 docs + 1 review + merge prep

        ## Your Task
        Analyze the project and output a JSON object with exactly this structure:
        ```json
        {
          "decision": "One sentence summary of your strategy",
          "summary": "Full markdown brief (see format below)",
          "assignments": [
            {
              "slotIndex": 0,
              "skillName": "backend",
              "agentType": "claude",
              "branch": "xroads/slot-1-backend",
              "taskDescription": "What this slot should do"
            },
            {
              "slotIndex": 1,
              "skillName": "frontend",
              "agentType": "claude",
              "branch": "xroads/slot-2-frontend",
              "taskDescription": "What this slot should do"
            },
            {
              "slotIndex": 2,
              "skillName": "testing",
              "agentType": "gemini",
              "branch": "xroads/slot-3-testing",
              "taskDescription": "What this slot should do"
            }
          ]
        }
        ```

        ## Brief Format (for the "summary" field)
        ```markdown
        ## Chairman Brief — {projectName}

        **Project**: {name}
        **Branches**: {branch list}
        **Recent activity**: {N} commits by {authors}
        **PRD**: {feature or "No active PRD"}
        **Domain detected**: {your domain assessment}
        **Phase**: BUILD / VERIFY / DELIVER

        ### Slot Strategy
        - **Slot 1** [{agent}] {role}: {task} → `{branch}`
        - **Slot 2** [{agent}] {role}: {task} → `{branch}`
        - **Slot 3** [{agent}] {role}: {task} → `{branch}`

        ### Rationale
        {Why you chose this distribution. Reference domain, PRD complexity, agent strengths, phase strategy.}
        ```

        ## Rules
        - Assign 3-6 slots (indices 0-5). Minimum 3, more if the project needs it.
        - Use claude for the hardest work, gemini for testing/review/docs
        - Branch names must start with "xroads/"
        - If PRD exists, map stories to slots. If not, analyze codebase for improvements.
        - Not every slot needs to code. Consider docs, review, testing roles.
        - Match agent strength to role: gemini excels at testing, claude at complex logic.
        - Output ONLY the JSON. No markdown fences, no explanation outside the JSON.
        """

        // Find claude binary
        let claudePath = Self.findClaude()

        guard let claudePath, FileManager.default.fileExists(atPath: claudePath) else {
            logger.warning("Claude CLI not found — falling back to demo chairman")
            return try await DemoCockpitCouncilClient().deliberate(input: input)
        }

        // Launch one-shot Claude Code for deliberation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--output-format", "json", "--max-turns", "1"]
        process.currentDirectoryURL = URL(fileURLWithPath: input.projectPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        logger.info("Chairman deliberating via Claude Code for \(projectName)...")

        do {
            try process.run()
        } catch {
            logger.error("Claude chairman launch failed: \(error.localizedDescription)")
            return try await DemoCockpitCouncilClient().deliberate(input: input)
        }

        // Wait with timeout (30 seconds max for deliberation)
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0,
              let outputString = String(data: outputData, encoding: .utf8),
              !outputString.isEmpty else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            logger.warning("Claude chairman failed (exit \(process.terminationStatus)): \(stderrString.prefix(200))")
            return try await DemoCockpitCouncilClient().deliberate(input: input)
        }

        // Parse the JSON output
        // Claude may wrap in markdown fences or add text — extract JSON
        let jsonString = Self.extractJSON(from: outputString)

        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.warning("Claude chairman output not valid UTF-8 — falling back")
            return try await DemoCockpitCouncilClient().deliberate(input: input)
        }

        do {
            let output = try JSONDecoder().decode(ChairmanOutput.self, from: jsonData)

            guard !output.assignments.isEmpty else {
                logger.warning("Claude chairman returned 0 assignments — falling back")
                return try await DemoCockpitCouncilClient().deliberate(input: input)
            }

            logger.info("Chairman deliberated: \(output.assignments.count) slots, domain: \(output.decision)")
            return output
        } catch {
            logger.warning("Claude chairman JSON parse failed: \(error.localizedDescription) — falling back")
            return try await DemoCockpitCouncilClient().deliberate(input: input)
        }
    }

    // MARK: - Helpers

    /// Extract JSON object from Claude's output (may be wrapped in markdown fences or have surrounding text)
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find JSON object boundaries
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    /// Find claude binary
    private static func findClaude() -> String? {
        let paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.nvm/versions/node/v20.19.4/bin/claude",
            "\(NSHomeDirectory())/.nvm/versions/node/v22.0.0/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude"
        ]

        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
}
