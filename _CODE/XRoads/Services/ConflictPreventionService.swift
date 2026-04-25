import Foundation
import os

// MARK: - ConflictPreventionResult

/// Result of analyzing a dispatch plan for potential file conflicts.
struct ConflictPreventionResult: Codable, Sendable {
    /// Pairs of stories that can safely run in parallel (no overlapping files).
    let safePairs: [(String, String)]
    /// Pairs of stories with predicted file overlaps.
    let riskyPairs: [(String, String)]
    /// Suggested resequencing to avoid conflicts.
    let recommendedResequencing: [[String]]

    enum CodingKeys: String, CodingKey {
        case safePairs, riskyPairs, recommendedResequencing
    }

    init(safePairs: [(String, String)], riskyPairs: [(String, String)], recommendedResequencing: [[String]]) {
        self.safePairs = safePairs
        self.riskyPairs = riskyPairs
        self.recommendedResequencing = recommendedResequencing
    }

    // Custom Codable for tuple arrays
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let safePairArrays = try container.decode([[String]].self, forKey: .safePairs)
        self.safePairs = safePairArrays.compactMap { arr in
            arr.count == 2 ? (arr[0], arr[1]) : nil
        }
        let riskyPairArrays = try container.decode([[String]].self, forKey: .riskyPairs)
        self.riskyPairs = riskyPairArrays.compactMap { arr in
            arr.count == 2 ? (arr[0], arr[1]) : nil
        }
        self.recommendedResequencing = try container.decode([[String]].self, forKey: .recommendedResequencing)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(safePairs.map { [$0.0, $0.1] }, forKey: .safePairs)
        try container.encode(riskyPairs.map { [$0.0, $0.1] }, forKey: .riskyPairs)
        try container.encode(recommendedResequencing, forKey: .recommendedResequencing)
    }
}

// MARK: - ConflictPreventionService

/// Predictive conflict prevention service that analyzes dispatch plans
/// to identify and resequence stories that would produce file conflicts.
actor ConflictPreventionService {

    private let logger = Logger(subsystem: "com.xroads", category: "ConflictPrevention")
    private let learningEngine: LearningEngine

    init(learningEngine: LearningEngine) {
        self.learningEngine = learningEngine
    }

    // MARK: - Analyze Dispatch Plan

    /// Analyze a set of stories and their predicted file patterns for conflicts.
    ///
    /// - Parameter stories: Array of (storyId, filePatterns) tuples
    /// - Returns: ConflictPreventionResult with safe/risky pairs and resequencing advice
    func analyzeDispatchPlan(stories: [(String, [String])]) async -> ConflictPreventionResult {
        var safePairs: [(String, String)] = []
        var riskyPairs: [(String, String)] = []

        // Check all pairs for overlapping file patterns
        for i in 0..<stories.count {
            for j in (i + 1)..<stories.count {
                let (storyA, patternsA) = stories[i]
                let (storyB, patternsB) = stories[j]

                let setA = Set(patternsA.map { $0.lowercased() })
                let setB = Set(patternsB.map { $0.lowercased() })
                let overlap = setA.intersection(setB)

                if overlap.isEmpty {
                    safePairs.append((storyA, storyB))
                } else {
                    riskyPairs.append((storyA, storyB))
                    logger.info("Risky pair: \(storyA) <-> \(storyB), overlap: \(overlap.count) files")
                }
            }
        }

        // Use existing conflict prediction from LearningEngine
        let predictions = await learningEngine.predictConflicts(stories: stories)

        // Build recommended resequencing
        let storyIds = stories.map(\.0)
        let resequencing = resequenceForSafety(
            layers: [storyIds],
            predictions: predictions
        )

        logger.info("Dispatch analysis: \(safePairs.count) safe, \(riskyPairs.count) risky pairs across \(stories.count) stories")

        return ConflictPreventionResult(
            safePairs: safePairs,
            riskyPairs: riskyPairs,
            recommendedResequencing: resequencing
        )
    }

    // MARK: - Resequence for Safety

    /// Move conflicting stories to sequential layers to avoid parallel execution.
    ///
    /// - Parameters:
    ///   - layers: Current execution layers (stories in same layer run in parallel)
    ///   - predictions: Predicted conflicts between story pairs
    /// - Returns: New layer arrangement with conflicting stories separated
    func resequenceForSafety(layers: [[String]], predictions: [ConflictPrediction]) -> [[String]] {
        guard !predictions.isEmpty else { return layers }

        // Flatten all stories
        let allStories = layers.flatMap { $0 }
        guard !allStories.isEmpty else { return layers }

        // Build conflict graph: storyId -> set of conflicting storyIds
        var conflicts: [String: Set<String>] = [:]
        for prediction in predictions {
            conflicts[prediction.storyA, default: []].insert(prediction.storyB)
            conflicts[prediction.storyB, default: []].insert(prediction.storyA)
        }

        // Greedy layer assignment: assign each story to the earliest layer
        // where it has no conflicts with existing stories in that layer.
        var newLayers: [[String]] = []

        for story in allStories {
            let storyConflicts = conflicts[story] ?? []
            var placed = false

            for layerIndex in 0..<newLayers.count {
                let layerStories = Set(newLayers[layerIndex])
                if storyConflicts.isDisjoint(with: layerStories) {
                    newLayers[layerIndex].append(story)
                    placed = true
                    break
                }
            }

            if !placed {
                newLayers.append([story])
            }
        }

        if newLayers.count > layers.count {
            logger.info("Resequenced from \(layers.count) to \(newLayers.count) layers to avoid \(predictions.count) conflicts")
        }

        return newLayers
    }

    // MARK: - Generate File Predictions

    /// Generate predicted file patterns for story titles using the learning engine's categorization.
    ///
    /// - Parameter storyTitles: Array of story titles
    /// - Returns: Dictionary mapping story title to predicted file patterns
    func generateFilePredictions(storyTitles: [String]) async -> [String: [String]] {
        var predictions: [String: [String]] = [:]

        for title in storyTitles {
            let category = await learningEngine.categorizeStory(title: title, filePatterns: [])

            // Generate predicted file patterns based on category
            let predictedPatterns: [String]
            switch category {
            case "backend_rust":
                predictedPatterns = ["src/*.rs", "Cargo.toml"]
            case "frontend_react":
                predictedPatterns = ["src/*.tsx", "src/*.ts", "package.json"]
            case "ios_swift":
                predictedPatterns = ["Sources/*.swift", "Package.swift"]
            case "testing":
                predictedPatterns = ["Tests/*.swift", "tests/*.rs", "src/__tests__/*.ts"]
            case "db_migration":
                predictedPatterns = ["migrations/*.sql", "src/db/*.rs"]
            case "devops":
                predictedPatterns = [".github/*.yml", "docker-compose.yml", "Dockerfile"]
            case "docs":
                predictedPatterns = ["docs/*.md", "README.md"]
            default:
                predictedPatterns = ["src/*"]
            }

            predictions[title] = predictedPatterns
        }

        return predictions
    }
}
