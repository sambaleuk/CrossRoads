import Foundation
import os

// MARK: - LearningEngineError

enum LearningEngineError: LocalizedError, Sendable {
    case noProfilesFound(String)
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .noProfilesFound(let category):
            return "No learning profiles found for category: \(category)"
        case .sessionNotFound(let id):
            return "Session not found for retro generation: \(id)"
        }
    }
}

// MARK: - AgentRecommendation

/// Recommendation for which agent type to assign to a task.
struct AgentRecommendation: Codable, Sendable {
    /// The recommended agent type (e.g., "claude", "gemini", "codex")
    let agentType: String
    /// Confidence score 0.0 - 1.0
    let confidence: Double
    /// Human-readable reason for the recommendation
    let reason: String
}

// MARK: - ConflictPrediction

/// Predicted file conflict between two concurrent stories.
struct ConflictPrediction: Codable, Sendable {
    /// First story identifier
    let storyA: String
    /// Second story identifier
    let storyB: String
    /// File patterns that overlap between the two stories
    let overlappingPatterns: [String]
    /// Risk level: low, medium, high
    let risk: String
}

// MARK: - LearningProfile

/// Aggregated performance data for an agent type on a task category.
/// Expected from LearningRepository.
struct LearningProfile: Codable, Sendable {
    let agentType: String
    let taskCategory: String
    let successRate: Double
    let avgCostCents: Double
    let avgDurationMs: Double
    let sampleCount: Int
}

// MARK: - StoryRecord

/// Minimal story record for retro generation. Expected from LearningRepository.
struct StoryRecord: Codable, Sendable {
    let storyId: String
    let title: String
    let status: String
    let agentType: String
    let durationMs: Int64
    let costCents: Int
    let errors: Int
}

// MARK: - LearningEngine

/// Analyzes historical agent performance to recommend agents, estimate task duration,
/// predict file conflicts, and generate retrospectives.
///
/// Uses pattern matching on file extensions for task categorization and scoring
/// formulas based on success rate, cost, and duration for agent recommendations.
actor LearningEngine {

    private let logger = Logger(subsystem: "com.xroads", category: "LearningEngine")
    private let learningRepository: LearningRepository

    init(learningRepository: LearningRepository) {
        self.learningRepository = learningRepository
    }

    // MARK: - Task Categorization

    /// Categorizes a story based on its title and the file patterns it touches.
    ///
    /// Rules (evaluated in order, first match wins):
    /// - .rs / .toml → backend_rust
    /// - .ts / .tsx → frontend_react
    /// - .swift → ios_swift
    /// - "test" in title or patterns → testing
    /// - .sql → db_migration
    /// - .yml / .yaml → devops
    /// - .md → docs
    /// - Default: general
    ///
    /// - Parameters:
    ///   - title: The story title
    ///   - filePatterns: Array of file path patterns the story will touch
    /// - Returns: Task category string
    func categorizeStory(title: String, filePatterns: [String]) -> String {
        let lowerTitle = title.lowercased()
        let allPatterns = filePatterns.joined(separator: " ").lowercased()
        let combined = lowerTitle + " " + allPatterns

        // Check file extensions in priority order
        if hasExtension(patterns: filePatterns, extensions: [".rs", ".toml"]) {
            return "backend_rust"
        }
        if hasExtension(patterns: filePatterns, extensions: [".ts", ".tsx"]) {
            return "frontend_react"
        }
        if hasExtension(patterns: filePatterns, extensions: [".swift"]) {
            return "ios_swift"
        }
        if combined.contains("test") {
            return "testing"
        }
        if hasExtension(patterns: filePatterns, extensions: [".sql"]) {
            return "db_migration"
        }
        if hasExtension(patterns: filePatterns, extensions: [".yml", ".yaml"]) {
            return "devops"
        }
        if hasExtension(patterns: filePatterns, extensions: [".md"]) {
            return "docs"
        }

        return "general"
    }

    // MARK: - Agent Recommendation

    /// Recommends the best agent type for a given task category based on historical performance.
    ///
    /// Scoring formula: score = successRate * 0.4 + (1/avgCost) * 0.3 + (1/avgDuration) * 0.3
    /// Returns the agent with the highest composite score.
    ///
    /// - Parameter taskCategory: The task category (from categorizeStory)
    /// - Returns: AgentRecommendation or nil if no historical data exists
    func recommendAgent(taskCategory: String) async -> AgentRecommendation? {
        guard let allProfiles = try? await learningRepository.fetchAllProfiles() else {
            return nil
        }
        let profiles = allProfiles.filter { $0.taskCategory == taskCategory && $0.totalExecutions > 0 }
        guard !profiles.isEmpty else {
            logger.info("No profiles for category '\(taskCategory)', no recommendation")
            return nil
        }

        let maxCost = Double(profiles.map(\.avgCostCents).max() ?? 1)
        let maxDuration = Double(profiles.map(\.avgDurationMs).max() ?? 1)

        var bestScore = -1.0
        var bestProfile: PerformanceProfile?

        for profile in profiles {
            let costScore = maxCost > 0 ? (1.0 - Double(profile.avgCostCents) / maxCost) : 0.0
            let durationScore = maxDuration > 0 ? (1.0 - Double(profile.avgDurationMs) / maxDuration) : 0.0
            let score = profile.successRate * 0.4 + costScore * 0.3 + durationScore * 0.3

            if score > bestScore {
                bestScore = score
                bestProfile = profile
            }
        }

        guard let winner = bestProfile else { return nil }

        let confidence = min(1.0, bestScore * (Double(winner.totalExecutions).squareRoot() / 10.0))

        let reason = String(
            format: "Best for %@: %.0f%% success, avg cost %d¢, avg time %ds (%d samples)",
            taskCategory,
            winner.successRate * 100,
            winner.avgCostCents,
            winner.avgDurationMs / 1000,
            winner.totalExecutions
        )

        return AgentRecommendation(
            agentType: winner.agentType,
            confidence: confidence,
            reason: reason
        )
    }

    // MARK: - Story Time Estimation

    /// Estimates the time to complete a story based on task category and complexity.
    ///
    /// Uses historical average duration adjusted by complexity multiplier:
    /// - simple: 0.5x
    /// - moderate: 1.0x
    /// - complex: 2.0x
    /// - critical: 3.0x
    ///
    /// - Parameters:
    ///   - taskCategory: The task category
    ///   - complexity: One of: simple, moderate, complex, critical
    /// - Returns: Estimated duration as TimeInterval (seconds), or nil if no data
    func estimateStoryTime(taskCategory: String, complexity: String) async -> TimeInterval? {
        guard let allProfiles = try? await learningRepository.fetchAllProfiles() else { return nil }
        let profiles = allProfiles.filter { $0.taskCategory == taskCategory && $0.totalExecutions > 0 }
        guard !profiles.isEmpty else { return nil }

        let totalSamples = profiles.reduce(0) { $0 + $1.totalExecutions }
        guard totalSamples > 0 else { return nil }

        let weightedDuration = profiles.reduce(0.0) { sum, profile in
            sum + Double(profile.avgDurationMs) * Double(profile.totalExecutions)
        } / Double(totalSamples)

        let multiplier = complexityMultiplier(for: complexity)
        let estimatedMs = weightedDuration * multiplier

        return estimatedMs / 1000.0  // Convert ms to seconds
    }

    // MARK: - Conflict Prediction

    /// Predicts potential file conflicts between concurrent stories.
    ///
    /// Compares file patterns between each pair of stories. Risk is determined by
    /// the number of overlapping patterns:
    /// - 1 overlap: low
    /// - 2-3 overlaps: medium
    /// - 4+ overlaps: high
    ///
    /// - Parameter stories: Array of (storyId, filePatterns) tuples
    /// - Returns: Array of ConflictPrediction for pairs with overlapping patterns
    func predictConflicts(stories: [(String, [String])]) -> [ConflictPrediction] {
        var predictions: [ConflictPrediction] = []

        for i in 0..<stories.count {
            for j in (i + 1)..<stories.count {
                let (storyA, patternsA) = stories[i]
                let (storyB, patternsB) = stories[j]

                let setA = Set(patternsA.map { normalizePattern($0) })
                let setB = Set(patternsB.map { normalizePattern($0) })
                let overlapping = setA.intersection(setB)

                if !overlapping.isEmpty {
                    let risk: String
                    switch overlapping.count {
                    case 1:
                        risk = "low"
                    case 2...3:
                        risk = "medium"
                    default:
                        risk = "high"
                    }

                    predictions.append(ConflictPrediction(
                        storyA: storyA,
                        storyB: storyB,
                        overlappingPatterns: Array(overlapping).sorted(),
                        risk: risk
                    ))
                }
            }
        }

        if !predictions.isEmpty {
            logger.info("Predicted \(predictions.count) potential conflicts across \(stories.count) stories")
        }

        return predictions
    }

    // MARK: - Retrospective Generation

    /// Generates a markdown retrospective document for a completed session.
    ///
    /// Includes:
    /// - Story completion table with status, agent, duration, cost, and errors
    /// - Agent leaderboard ranked by success rate
    /// - Anomalies (stories with errors or excessive cost/duration)
    /// - Recommendations for future sessions
    ///
    /// - Parameter sessionId: The cockpit session to generate a retro for
    /// - Returns: Markdown-formatted retrospective document
    func generateRetro(sessionId: UUID) async throws -> String {
        let records = try await learningRepository.fetchRecords(sessionId: sessionId)

        guard !records.isEmpty else {
            throw LearningEngineError.sessionNotFound(sessionId)
        }

        // Convert LearningRecord to StoryRecord for retro
        let stories = records.map { r in
            StoryRecord(
                storyId: r.storyId, title: r.storyTitle,
                status: r.success ? "done" : "failed",
                agentType: r.agentType,
                durationMs: Int64(r.durationMs), costCents: r.costCents,
                errors: r.testsFailed + r.conflictsEncountered
            )
        }

        var md = "# Session Retrospective\n\n"
        md += "**Session**: \(sessionId)\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        md += "## Stories\n\n"
        md += "| Story | Status | Agent | Duration | Cost | Errors |\n"
        md += "|-------|--------|-------|----------|------|--------|\n"

        for story in stories {
            let durationStr = formatDuration(ms: story.durationMs)
            let costStr = formatCost(cents: story.costCents)
            md += "| \(story.title) | \(story.status) | \(story.agentType) | \(durationStr) | \(costStr) | \(story.errors) |\n"
        }

        // Agent leaderboard
        md += "\n## Agent Leaderboard\n\n"
        let agentStats = computeAgentStats(stories: stories)

        md += "| Agent | Stories | Success Rate | Avg Duration | Total Cost |\n"
        md += "|-------|---------|-------------|-------------|------------|\n"

        for stat in agentStats.sorted(by: { $0.successRate > $1.successRate }) {
            md += "| \(stat.agentType) | \(stat.storyCount) | \(String(format: "%.0f%%", stat.successRate * 100)) | \(stat.avgDuration) | \(stat.totalCost) |\n"
        }

        // Anomalies
        let anomalies = detectAnomalies(stories: stories)
        if !anomalies.isEmpty {
            md += "\n## Anomalies\n\n"
            for anomaly in anomalies {
                md += "- \(anomaly)\n"
            }
        }

        // Recommendations
        md += "\n## Recommendations\n\n"
        let recommendations = generateRecommendations(stories: stories, agentStats: agentStats)
        for rec in recommendations {
            md += "- \(rec)\n"
        }

        logger.info("Generated retro for session \(sessionId): \(stories.count) stories, \(agentStats.count) agents")

        return md
    }

    // MARK: - Private Helpers

    private func hasExtension(patterns: [String], extensions: [String]) -> Bool {
        patterns.contains { pattern in
            let lower = pattern.lowercased()
            return extensions.contains { lower.hasSuffix($0) }
        }
    }

    private func complexityMultiplier(for complexity: String) -> Double {
        switch complexity.lowercased() {
        case "simple": return 0.5
        case "moderate": return 1.0
        case "complex": return 2.0
        case "critical": return 3.0
        default: return 1.0
        }
    }

    /// Normalizes a file pattern for comparison (lowercased, extract directory + extension).
    private func normalizePattern(_ pattern: String) -> String {
        let lower = pattern.lowercased()
        // Extract the directory component for comparison
        let components = lower.split(separator: "/")
        if components.count > 1 {
            // Keep directory + filename for granular conflict detection
            return components.suffix(2).joined(separator: "/")
        }
        return lower
    }

    // MARK: - Retro Helpers

    private struct AgentStat {
        let agentType: String
        let storyCount: Int
        let successRate: Double
        let avgDuration: String
        let totalCost: String
    }

    private func computeAgentStats(stories: [StoryRecord]) -> [AgentStat] {
        let grouped = Dictionary(grouping: stories, by: \.agentType)

        return grouped.map { agentType, agentStories in
            let completedCount = agentStories.filter { $0.status == "done" || $0.status == "completed" }.count
            let successRate = agentStories.isEmpty ? 0.0 : Double(completedCount) / Double(agentStories.count)
            let avgMs = agentStories.isEmpty ? 0 : agentStories.reduce(Int64(0)) { $0 + $1.durationMs } / Int64(agentStories.count)
            let totalCents = agentStories.reduce(0) { $0 + $1.costCents }

            return AgentStat(
                agentType: agentType,
                storyCount: agentStories.count,
                successRate: successRate,
                avgDuration: formatDuration(ms: avgMs),
                totalCost: formatCost(cents: totalCents)
            )
        }
    }

    private func detectAnomalies(stories: [StoryRecord]) -> [String] {
        var anomalies: [String] = []

        // Stories with errors
        let errorStories = stories.filter { $0.errors > 0 }
        for story in errorStories {
            anomalies.append("**\(story.title)**: \(story.errors) error(s) during execution")
        }

        // Compute average duration and cost to detect outliers
        let avgDuration = stories.isEmpty ? 0.0 : Double(stories.reduce(Int64(0)) { $0 + $1.durationMs }) / Double(stories.count)
        let avgCost = stories.isEmpty ? 0.0 : Double(stories.reduce(0) { $0 + $1.costCents }) / Double(stories.count)

        for story in stories {
            if Double(story.durationMs) > avgDuration * 3.0 {
                anomalies.append("**\(story.title)**: took \(formatDuration(ms: story.durationMs)), 3x+ above average")
            }
            if Double(story.costCents) > avgCost * 3.0 {
                anomalies.append("**\(story.title)**: cost \(formatCost(cents: story.costCents)), 3x+ above average")
            }
        }

        return anomalies
    }

    private func generateRecommendations(stories: [StoryRecord], agentStats: [AgentStat]) -> [String] {
        var recs: [String] = []

        // Recommend best agent overall
        if let best = agentStats.max(by: { $0.successRate < $1.successRate }), best.successRate > 0 {
            recs.append("Best performing agent: **\(best.agentType)** (\(String(format: "%.0f%%", best.successRate * 100)) success rate)")
        }

        // Warn about agents with low success rates
        for stat in agentStats where stat.successRate < 0.5 && stat.storyCount >= 2 {
            recs.append("Consider replacing **\(stat.agentType)** for similar tasks (only \(String(format: "%.0f%%", stat.successRate * 100)) success rate)")
        }

        // Overall error rate
        let totalErrors = stories.reduce(0) { $0 + $1.errors }
        if totalErrors > stories.count {
            recs.append("High error rate (\(totalErrors) errors across \(stories.count) stories). Consider adding more validation gates.")
        }

        if recs.isEmpty {
            recs.append("Session completed normally. No specific recommendations.")
        }

        return recs
    }

    private func formatDuration(ms: Int64) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds >= 3600 {
            return String(format: "%.1fh", seconds / 3600.0)
        }
        if seconds >= 60 {
            return String(format: "%.0fm", seconds / 60.0)
        }
        return String(format: "%.0fs", seconds)
    }

    private func formatCost(cents: Int) -> String {
        if cents >= 100 {
            return String(format: "$%.2f", Double(cents) / 100.0)
        }
        return "\(cents)¢"
    }
}
