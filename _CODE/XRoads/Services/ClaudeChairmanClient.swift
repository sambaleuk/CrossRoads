import Foundation
import os

// MARK: - ClaudeChairmanClient

/// The Chairman is an ANALYST, not a decision-maker.
///
/// It reads the project context (git, PRD, branches) and produces a structured
/// analysis report. The cockpit brain receives this report and decides whether
/// to launch slots, how many, and with what roles.
///
/// The chairman can still produce default slot assignments as a SUGGESTION,
/// but the brain has the final say.
final class ClaudeChairmanClient: CockpitCouncilClientProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.xroads", category: "ClaudeChairman")

    func deliberate(input: ChairmanInput) async throws -> ChairmanOutput {
        let projectName = (input.projectPath as NSString).lastPathComponent
        let suite = Suite.builtIn.first(where: { $0.id == input.suiteId }) ?? .developer

        let branchList = input.openBranches.prefix(10).joined(separator: ", ")
        let commitCount = input.gitLog.count
        let recentAuthors = Set(input.gitLog.prefix(10).map { $0.author }).joined(separator: ", ")

        // PRD analysis — include all discovered PRDs
        var prdSection = "No PRDs detected in project."
        var storyCount = 0
        var pendingCount = 0
        if !input.prdSummaries.isEmpty {
            let lines = input.prdSummaries.map { prd in
                "- **\(prd.featureName)**: \(prd.totalStories) stories (\(prd.pendingStories) pending, \(prd.completedStories) done) — \(prd.status)"
            }
            prdSection = "PRDs (\(input.prdSummaries.count)):\n\(lines.joined(separator: "\n"))"
            storyCount = input.prdSummaries.reduce(0) { $0 + $1.totalStories }
            pendingCount = input.prdSummaries.reduce(0) { $0 + $1.pendingStories }
        }

        // Domain detection from branches + commits
        let allText = (input.openBranches + input.gitLog.map { $0.message }).joined(separator: " ").lowercased()
        let domain = detectDomain(from: allText)

        // Build the chairman analysis (NOT slot assignments — those are suggestions)
        let analysis = """
        ## Chairman Analysis — \(projectName)

        **Project**: \(projectName)
        **Path**: \(input.projectPath)
        **Branches**: \(branchList.isEmpty ? "main" : branchList)
        **Recent activity**: \(commitCount) commits by \(recentAuthors.isEmpty ? "unknown" : recentAuthors)
        **\(prdSection)**
        **Domain**: \(domain)
        **Suite**: \(suite.name) (\(suite.roles.count) roles available)

        ### Available Roles
        \(suite.roles.map { "- **\($0.id)** (\($0.name)): \($0.description)" }.joined(separator: "\n"))

        ### Phases
        \(suite.phases.map { "- \($0.name): \($0.description)" }.joined(separator: "\n"))

        ### Recommendation
        \(generateRecommendation(storyCount: storyCount, pendingCount: pendingCount, domain: domain, suite: suite))
        """

        // Generate default assignments as SUGGESTIONS (brain may override)
        let assignments = generateSuggestedAssignments(
            projectName: projectName,
            domain: domain,
            storyCount: storyCount,
            pendingCount: pendingCount,
            suite: suite
        )

        let decision = pendingCount > 0
            ? "PRD with \(pendingCount) pending stories — \(domain) domain"
            : "No PRD — general project analysis for \(domain) domain"

        logger.info("Chairman analysis complete: \(domain), \(assignments.count) suggested slots")

        return ChairmanOutput(
            decision: decision,
            summary: analysis,
            assignments: assignments
        )
    }

    // MARK: - Domain Detection

    private func detectDomain(from text: String) -> String {
        let domains: [(String, [String])] = [
            ("authentication", ["auth", "login", "password", "session", "jwt", "oauth"]),
            ("api", ["api", "endpoint", "rest", "graphql", "route", "middleware"]),
            ("frontend", ["react", "vue", "component", "ui", "css", "tailwind", "frontend"]),
            ("backend", ["server", "database", "migration", "model", "service", "backend"]),
            ("devops", ["deploy", "docker", "ci", "cd", "pipeline", "infrastructure"]),
            ("data-pipeline", ["data", "etl", "pipeline", "analytics", "ml"]),
            ("payments", ["payment", "stripe", "billing", "subscription", "invoice"]),
            ("mobile", ["ios", "android", "swift", "kotlin", "flutter", "react-native"]),
        ]

        var best = ("general", 0)
        for (domain, keywords) in domains {
            let score = keywords.filter { text.contains($0) }.count
            if score > best.1 { best = (domain, score) }
        }
        return best.0
    }

    // MARK: - Recommendation

    private func generateRecommendation(storyCount: Int, pendingCount: Int, domain: String, suite: Suite) -> String {
        if pendingCount == 0 && storyCount == 0 {
            return """
            No PRD loaded. The brain should:
            1. Scan the codebase to understand the project
            2. Decide if any improvements are needed
            3. Optionally launch 1 agent for analysis or documentation
            The brain decides — no slots launched automatically.
            """
        }

        if pendingCount <= 3 {
            return """
            Small scope (\(pendingCount) stories). Suggest 1-2 agents:
            - 1 implementer for the stories
            - 1 tester if stories involve critical logic
            The brain decides based on complexity.
            """
        }

        if pendingCount <= 6 {
            return """
            Medium scope (\(pendingCount) stories). Suggest 2-3 agents:
            - 1-2 implementers for parallel work
            - 1 tester or reviewer
            The brain decides the exact split.
            """
        }

        return """
        Large scope (\(pendingCount) stories). Suggest 3+ agents:
        - 2-3 implementers across different story groups
        - 1 tester for quality
        - Consider 1 documentation slot
        The brain decides based on dependencies and domain.
        """
    }

    // MARK: - Suggested Assignments

    private func generateSuggestedAssignments(
        projectName: String,
        domain: String,
        storyCount: Int,
        pendingCount: Int,
        suite: Suite
    ) -> [SlotAssignment] {
        // The chairman SUGGESTS — brain has final say
        // Fewer slots by default, brain can launch more if needed

        guard pendingCount > 0 else {
            // No PRD: suggest 0 slots — brain decides if it wants to launch anything
            return []
        }

        if pendingCount <= 3 {
            // Small: 1 implementer only
            return [
                SlotAssignment(slotIndex: 0, skillName: "backend", agentType: "claude",
                    branch: "xroads/slot-1-\(domain)", taskDescription: "Implement \(pendingCount) pending stories")
            ]
        }

        // Medium/large: 2 slots — implementer + tester
        return [
            SlotAssignment(slotIndex: 0, skillName: "backend", agentType: "claude",
                branch: "xroads/slot-1-core", taskDescription: "Core implementation: primary stories"),
            SlotAssignment(slotIndex: 1, skillName: "testing", agentType: "gemini",
                branch: "xroads/slot-2-quality", taskDescription: "Quality: tests, code review")
        ]
    }
}
