import Foundation

// MARK: - DemoCockpitCouncilClient

/// Context-aware council client that analyzes the actual project data
/// from ChairmanInput to produce relevant slot assignments and briefs.
/// Replaces the hardcoded demo with real project analysis.
final class DemoCockpitCouncilClient: CockpitCouncilClientProtocol, @unchecked Sendable {

    func deliberate(input: ChairmanInput) async throws -> ChairmanOutput {
        // Brief delay to feel deliberate
        try await Task.sleep(for: .milliseconds(500))

        let projectName = (input.projectPath as NSString).lastPathComponent
        let branchList = input.openBranches.isEmpty ? "main" : input.openBranches.prefix(5).joined(separator: ", ")
        let commitCount = input.gitLog.count
        let recentAuthors = Set(input.gitLog.prefix(10).map { $0.author }).joined(separator: ", ")

        // Analyze PRD if available
        let prdContext: String
        let storyCount: Int
        let featureName: String

        if let prd = input.prdSummary {
            featureName = prd.featureName
            storyCount = prd.totalStories
            let pendingCount = prd.pendingStories
            prdContext = """
                **PRD**: \(prd.featureName)
                Stories: \(storyCount) total, \(pendingCount) pending
                Status: \(prd.status)
                """
        } else {
            featureName = projectName
            storyCount = 0
            prdContext = "**PRD**: No active PRD detected. Agents will work on general improvements."
        }

        // Analyze project domain from branches + commits
        let allText = (input.openBranches + input.gitLog.map { $0.message }).joined(separator: " ").lowercased()
        let domain = detectDomain(from: allText)
        let assignments = generateAssignments(
            projectName: projectName,
            featureName: featureName,
            domain: domain,
            storyCount: storyCount,
            branches: input.openBranches
        )

        // Build contextual brief
        let summary = """
            ## Chairman Brief — \(projectName)

            **Project**: \(projectName)
            **Branches**: \(branchList)\(input.openBranches.count > 5 ? " (+\(input.openBranches.count - 5) more)" : "")
            **Recent activity**: \(commitCount) commits\(recentAuthors.isEmpty ? "" : " by \(recentAuthors)")
            \(prdContext)
            **Domain detected**: \(domain)

            ### Slot Strategy
            \(assignments.enumerated().map { i, a in
                "- **Slot \(i + 1)** [\(a.agentType)]: \(a.taskDescription) → `\(a.branch)`"
            }.joined(separator: "\n"))

            ### Rationale
            \(generateRationale(domain: domain, storyCount: storyCount, assignments: assignments))
            """

        return ChairmanOutput(
            decision: "Context-aware assignment: \(assignments.count) agents on \(projectName) (\(domain))",
            summary: summary,
            assignments: assignments
        )
    }

    // MARK: - Domain Detection

    private func detectDomain(from text: String) -> String {
        let domainKeywords: [(String, [String])] = [
            ("authentication", ["auth", "login", "password", "session", "jwt", "oauth"]),
            ("api-development", ["api", "endpoint", "rest", "graphql", "route", "middleware"]),
            ("frontend", ["react", "vue", "component", "ui", "css", "tailwind", "frontend"]),
            ("backend", ["server", "database", "migration", "model", "service", "backend"]),
            ("devops", ["deploy", "docker", "ci", "cd", "pipeline", "infrastructure", "k8s"]),
            ("data-pipeline", ["data", "etl", "pipeline", "analytics", "ml", "model"]),
            ("payments", ["payment", "stripe", "billing", "subscription", "invoice"]),
            ("observability", ["monitor", "trace", "log", "metric", "observability", "telemetry"]),
            ("security", ["security", "audit", "vulnerability", "encryption", "compliance"]),
        ]

        var scores: [(String, Int)] = []
        for (domain, keywords) in domainKeywords {
            let score = keywords.reduce(0) { count, keyword in
                count + (text.contains(keyword) ? 1 : 0)
            }
            if score > 0 { scores.append((domain, score)) }
        }

        return scores.sorted(by: { $0.1 > $1.1 }).first?.0 ?? "general-development"
    }

    // MARK: - Assignment Generation

    private func generateAssignments(
        projectName: String,
        featureName: String,
        domain: String,
        storyCount: Int,
        branches: [String]
    ) -> [SlotAssignment] {
        let branchPrefix = "xroads/\(featureName.lowercased().replacingOccurrences(of: " ", with: "-").prefix(30))"

        // Domain-specific slot strategies
        switch domain {
        case "authentication":
            return [
                SlotAssignment(slotIndex: 0, skillName: "backend", agentType: "claude",
                    branch: "\(branchPrefix)-auth-core",
                    taskDescription: "Auth core: JWT/session management, password hashing, middleware"),
                SlotAssignment(slotIndex: 1, skillName: "frontend", agentType: "claude",
                    branch: "\(branchPrefix)-auth-ui",
                    taskDescription: "Auth UI: login/register forms, protected routes, token handling"),
                SlotAssignment(slotIndex: 2, skillName: "testing", agentType: "gemini",
                    branch: "\(branchPrefix)-auth-tests",
                    taskDescription: "Auth tests: security edge cases, session expiry, brute force protection"),
            ]

        case "api-development":
            return [
                SlotAssignment(slotIndex: 0, skillName: "backend", agentType: "claude",
                    branch: "\(branchPrefix)-api-endpoints",
                    taskDescription: "API endpoints: CRUD routes, validation, error handling"),
                SlotAssignment(slotIndex: 1, skillName: "backend", agentType: "claude",
                    branch: "\(branchPrefix)-api-models",
                    taskDescription: "Data layer: models, migrations, repository pattern"),
                SlotAssignment(slotIndex: 2, skillName: "testing", agentType: "gemini",
                    branch: "\(branchPrefix)-api-tests",
                    taskDescription: "API tests: integration tests, contract validation, edge cases"),
            ]

        case "frontend":
            return [
                SlotAssignment(slotIndex: 0, skillName: "frontend", agentType: "claude",
                    branch: "\(branchPrefix)-components",
                    taskDescription: "UI components: reusable components, design system, accessibility"),
                SlotAssignment(slotIndex: 1, skillName: "frontend", agentType: "claude",
                    branch: "\(branchPrefix)-state",
                    taskDescription: "State management: stores, data fetching, caching"),
                SlotAssignment(slotIndex: 2, skillName: "testing", agentType: "gemini",
                    branch: "\(branchPrefix)-ui-tests",
                    taskDescription: "UI tests: component tests, snapshot tests, E2E flows"),
            ]

        case "observability":
            return [
                SlotAssignment(slotIndex: 0, skillName: "backend", agentType: "claude",
                    branch: "\(branchPrefix)-ingestion",
                    taskDescription: "Data ingestion: SDK, proxy mode, event processing pipeline"),
                SlotAssignment(slotIndex: 1, skillName: "backend", agentType: "claude",
                    branch: "\(branchPrefix)-dashboard",
                    taskDescription: "Dashboard: real-time metrics, cost analytics, query builder"),
                SlotAssignment(slotIndex: 2, skillName: "testing", agentType: "gemini",
                    branch: "\(branchPrefix)-integration",
                    taskDescription: "Integration: end-to-end pipeline tests, load testing, data validation"),
            ]

        default:
            // Generic but still contextual
            return [
                SlotAssignment(slotIndex: 0, skillName: "backend", agentType: "claude",
                    branch: "\(branchPrefix)-core",
                    taskDescription: "Core implementation: business logic, data models, services"),
                SlotAssignment(slotIndex: 1, skillName: "frontend", agentType: "claude",
                    branch: "\(branchPrefix)-interface",
                    taskDescription: "Interface: UI components, user flows, API integration"),
                SlotAssignment(slotIndex: 2, skillName: "testing", agentType: "gemini",
                    branch: "\(branchPrefix)-quality",
                    taskDescription: "Quality: unit tests, integration tests, code review"),
            ]
        }
    }

    // MARK: - Rationale

    private func generateRationale(domain: String, storyCount: Int, assignments: [SlotAssignment]) -> String {
        var lines: [String] = []

        lines.append("Domain **\(domain)** detected from branch names and commit history.")

        if storyCount > 0 {
            lines.append("\(storyCount) stories to implement — distributed across \(assignments.count) parallel agents.")
        } else {
            lines.append("No PRD loaded — agents will analyze codebase and work on detected improvements.")
        }

        let claudeCount = assignments.filter { $0.agentType == "claude" }.count
        let geminiCount = assignments.filter { $0.agentType == "gemini" }.count
        if claudeCount > 0 { lines.append("Claude Code ×\(claudeCount) for primary implementation (strongest on complex logic).") }
        if geminiCount > 0 { lines.append("Gemini CLI ×\(geminiCount) for testing (fast, cost-effective for test generation).") }

        lines.append("Each agent gets an isolated git worktree — no merge conflicts during parallel work.")

        return lines.joined(separator: "\n")
    }
}
