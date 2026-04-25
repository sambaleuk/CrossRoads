import Foundation
import os

// MARK: - StoryFeatures

/// Feature vector extracted from a story for ML predictions.
struct StoryFeatures: Codable, Sendable {
    let filesChanged: Int
    let linesAdded: Int
    let linesRemoved: Int
    let testsRun: Int
    /// 0 = simple, 1 = moderate, 2 = complex, 3 = critical
    let complexityScore: Int
    let fileExtensions: [String]

    /// Build from a LearningRecord.
    init(from record: LearningRecord) {
        self.filesChanged = record.filesChanged
        self.linesAdded = record.linesAdded
        self.linesRemoved = record.linesRemoved
        self.testsRun = record.testsRun
        self.complexityScore = Self.complexityToScore(record.storyComplexity)
        self.fileExtensions = Self.extractExtensions(from: record.filePatterns)
    }

    init(
        filesChanged: Int,
        linesAdded: Int,
        linesRemoved: Int,
        testsRun: Int,
        complexityScore: Int,
        fileExtensions: [String]
    ) {
        self.filesChanged = filesChanged
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.testsRun = testsRun
        self.complexityScore = complexityScore
        self.fileExtensions = fileExtensions
    }

    /// Convert complexity string to numeric score.
    static func complexityToScore(_ complexity: String) -> Int {
        switch complexity.lowercased() {
        case "simple": return 0
        case "moderate": return 1
        case "complex": return 2
        case "critical": return 3
        default: return 1
        }
    }

    /// Extract file extensions from the JSON-encoded filePatterns string.
    static func extractExtensions(from filePatterns: String) -> [String] {
        guard let data = filePatterns.data(using: .utf8),
              let patterns = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return patterns.compactMap { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return ext.isEmpty ? nil : ext
        }
    }

    /// Feature vector for regression: [filesChanged, linesAdded, linesRemoved, testsRun, complexityScore]
    var regressionVector: [Double] {
        [
            Double(filesChanged),
            Double(linesAdded),
            Double(linesRemoved),
            Double(testsRun),
            Double(complexityScore)
        ]
    }
}

// MARK: - LinearRegressionModel

/// Ordinary Least Squares linear regression for time estimation.
/// Solves weights = (X^T X)^-1 X^T y using hand-written matrix math.
/// Feature dimension is fixed at 5 (plus intercept = 6 weights).
struct LinearRegressionModel: Codable, Sendable {
    /// Weights: [intercept, filesChanged, linesAdded, linesRemoved, testsRun, complexityScore]
    var weights: [Double]

    /// Number of training samples used.
    var sampleCount: Int

    /// Predict duration in milliseconds from a feature vector.
    func predict(features: [Double]) -> Double {
        guard weights.count == features.count + 1 else { return 0 }
        var result = weights[0] // intercept
        for i in 0..<features.count {
            result += weights[i + 1] * features[i]
        }
        return max(0, result) // duration can't be negative
    }

    // MARK: - Matrix Operations (max 6x6)

    /// Train from feature rows and target values.
    /// Uses closed-form OLS: w = (X^T X)^-1 X^T y
    /// X is augmented with a leading 1 column for intercept.
    static func train(features: [[Double]], targets: [Double]) -> LinearRegressionModel? {
        let n = features.count
        guard n > 0, let dim = features.first?.count, dim > 0 else { return nil }

        let augDim = dim + 1 // +1 for intercept

        // Need at least augDim samples for a well-determined system
        guard n >= augDim else { return nil }

        // Build augmented feature matrix X (n x augDim) with leading 1s
        var X: [[Double]] = features.map { row in
            var augmented = [1.0] // intercept term
            augmented.append(contentsOf: row)
            return augmented
        }

        // Compute X^T X (augDim x augDim)
        var XtX = Array(repeating: Array(repeating: 0.0, count: augDim), count: augDim)
        for i in 0..<augDim {
            for j in 0..<augDim {
                var sum = 0.0
                for k in 0..<n {
                    sum += X[k][i] * X[k][j]
                }
                XtX[i][j] = sum
            }
        }

        // Compute X^T y (augDim x 1)
        var Xty = Array(repeating: 0.0, count: augDim)
        for i in 0..<augDim {
            var sum = 0.0
            for k in 0..<n {
                sum += X[k][i] * targets[k]
            }
            Xty[i] = sum
        }

        // Invert X^T X using Gauss-Jordan elimination
        guard let XtXinv = invertMatrix(XtX) else { return nil }

        // Multiply (X^T X)^-1 * X^T y to get weights
        var weights = Array(repeating: 0.0, count: augDim)
        for i in 0..<augDim {
            var sum = 0.0
            for j in 0..<augDim {
                sum += XtXinv[i][j] * Xty[j]
            }
            weights[i] = sum
        }

        return LinearRegressionModel(weights: weights, sampleCount: n)
    }

    /// Gauss-Jordan matrix inversion for small square matrices.
    /// Returns nil if the matrix is singular.
    private static func invertMatrix(_ matrix: [[Double]]) -> [[Double]]? {
        let n = matrix.count
        guard n > 0 else { return nil }

        // Augment with identity: [matrix | I]
        var aug = matrix.map { row -> [Double] in
            var r = row
            r.append(contentsOf: Array(repeating: 0.0, count: n))
            return r
        }
        for i in 0..<n {
            aug[i][n + i] = 1.0
        }

        // Forward elimination with partial pivoting
        for col in 0..<n {
            // Find pivot
            var maxVal = abs(aug[col][col])
            var maxRow = col
            for row in (col + 1)..<n {
                let val = abs(aug[row][col])
                if val > maxVal {
                    maxVal = val
                    maxRow = row
                }
            }

            if maxVal < 1e-12 {
                return nil // Singular matrix
            }

            // Swap rows
            if maxRow != col {
                aug.swapAt(col, maxRow)
            }

            // Scale pivot row
            let pivot = aug[col][col]
            for j in 0..<(2 * n) {
                aug[col][j] /= pivot
            }

            // Eliminate column
            for row in 0..<n where row != col {
                let factor = aug[row][col]
                for j in 0..<(2 * n) {
                    aug[row][j] -= factor * aug[col][j]
                }
            }
        }

        // Extract inverse from right half
        return aug.map { Array($0[n..<(2 * n)]) }
    }
}

// MARK: - NaiveBayesClassifier

/// Multinomial Naive Bayes for story categorization.
/// Uses word frequencies from title and file extension presence.
struct NaiveBayesClassifier: Codable, Sendable {

    static let categories = [
        "backend_rust", "frontend_react", "ios_swift", "testing",
        "db_migration", "devops", "docs", "general"
    ]

    /// Word counts per category: [category: [word: count]]
    var wordCounts: [String: [String: Int]]

    /// Total word count per category
    var categoryWordTotals: [String: Int]

    /// Number of documents per category
    var categoryDocCounts: [String: Int]

    /// Total documents seen during training
    var totalDocuments: Int

    /// All unique words in vocabulary
    var vocabularySize: Int

    /// Classify a story by title and file patterns.
    /// Returns the most probable category using Bayes theorem with Laplace smoothing.
    func classify(title: String, filePatterns: [String]) -> String {
        let words = tokenize(title: title, filePatterns: filePatterns)
        guard !words.isEmpty else { return "general" }

        var bestCategory = "general"
        var bestLogProb = -Double.infinity

        for category in Self.categories {
            // Prior: P(category) = docCount / totalDocuments (with Laplace)
            let docCount = Double(categoryDocCounts[category] ?? 0)
            let logPrior = log((docCount + 1.0) / (Double(totalDocuments) + Double(Self.categories.count)))

            // Likelihood: product of P(word|category) for each word
            let catWords = wordCounts[category] ?? [:]
            let catTotal = Double(categoryWordTotals[category] ?? 0)
            let vocabSize = Double(vocabularySize)

            var logLikelihood = 0.0
            for word in words {
                let wordCount = Double(catWords[word] ?? 0)
                // Laplace smoothing: (count + 1) / (total + vocabSize)
                logLikelihood += log((wordCount + 1.0) / (catTotal + vocabSize))
            }

            let logProb = logPrior + logLikelihood
            if logProb > bestLogProb {
                bestLogProb = logProb
                bestCategory = category
            }
        }

        return bestCategory
    }

    /// Train from labeled documents.
    static func train(documents: [(title: String, filePatterns: [String], category: String)]) -> NaiveBayesClassifier {
        var wordCounts: [String: [String: Int]] = [:]
        var categoryWordTotals: [String: Int] = [:]
        var categoryDocCounts: [String: Int] = [:]
        var allWords: Set<String> = []

        // Initialize categories
        for cat in categories {
            wordCounts[cat] = [:]
            categoryWordTotals[cat] = 0
            categoryDocCounts[cat] = 0
        }

        for doc in documents {
            let category = categories.contains(doc.category) ? doc.category : "general"
            categoryDocCounts[category, default: 0] += 1

            let words = tokenize(title: doc.title, filePatterns: doc.filePatterns)
            for word in words {
                allWords.insert(word)
                wordCounts[category, default: [:]][word, default: 0] += 1
                categoryWordTotals[category, default: 0] += 1
            }
        }

        return NaiveBayesClassifier(
            wordCounts: wordCounts,
            categoryWordTotals: categoryWordTotals,
            categoryDocCounts: categoryDocCounts,
            totalDocuments: documents.count,
            vocabularySize: allWords.count
        )
    }

    /// Tokenize a story into words for classification.
    /// Extracts: lowercased title words + file extension tokens (e.g., "ext_rs", "ext_swift").
    private static func tokenize(title: String, filePatterns: [String]) -> [String] {
        var tokens: [String] = []

        // Title words: lowercased, alphanumeric only, min 2 chars
        let titleWords = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        tokens.append(contentsOf: titleWords)

        // File extension tokens
        for pattern in filePatterns {
            let ext = (pattern as NSString).pathExtension.lowercased()
            if !ext.isEmpty {
                tokens.append("ext_\(ext)")
            }
            // Directory tokens (first path component)
            let components = pattern.lowercased().split(separator: "/")
            if let dir = components.first, components.count > 1 {
                tokens.append("dir_\(dir)")
            }
        }

        return tokens
    }

    /// Instance tokenize for prediction (calls static version).
    private func tokenize(title: String, filePatterns: [String]) -> [String] {
        Self.tokenize(title: title, filePatterns: filePatterns)
    }
}

// MARK: - DecisionTreeModel

/// Single-feature decision stump for conflict prediction.
/// Picks the one feature + threshold that maximizes information gain.
struct DecisionTreeModel: Codable, Sendable {

    /// Index of the feature used for splitting.
    var featureIndex: Int

    /// Threshold value: predict conflict if feature > threshold.
    var threshold: Double

    /// Base conflict rate across all training data.
    var baseConflictRate: Double

    /// Conflict rate when feature > threshold.
    var aboveThresholdRate: Double

    /// Conflict rate when feature <= threshold.
    var belowThresholdRate: Double

    /// Number of training samples.
    var sampleCount: Int

    /// Feature names for logging.
    static let featureNames = [
        "file_overlap_count", "directory_overlap", "extension_match", "historical_conflict_rate"
    ]

    /// Predict conflict probability for a feature vector.
    func predict(features: [Double]) -> Double {
        guard featureIndex < features.count else { return baseConflictRate }
        if features[featureIndex] > threshold {
            return aboveThresholdRate
        } else {
            return belowThresholdRate
        }
    }

    /// Train a decision stump from labeled examples.
    /// Features: [file_overlap_count, directory_overlap, extension_match, historical_conflict_rate]
    /// Labels: 1.0 for conflict, 0.0 for no conflict.
    static func train(features: [[Double]], labels: [Double]) -> DecisionTreeModel? {
        let n = features.count
        guard n > 0, let dim = features.first?.count, dim > 0 else { return nil }

        let positives = labels.reduce(0.0, +)
        let baseRate = positives / Double(n)

        // If all same class, return trivial stump
        if baseRate == 0.0 || baseRate == 1.0 {
            return DecisionTreeModel(
                featureIndex: 0, threshold: 0.0,
                baseConflictRate: baseRate,
                aboveThresholdRate: baseRate, belowThresholdRate: baseRate,
                sampleCount: n
            )
        }

        let baseEntropy = binaryEntropy(baseRate)

        var bestGain = -1.0
        var bestFeatureIdx = 0
        var bestThreshold = 0.0
        var bestAboveRate = baseRate
        var bestBelowRate = baseRate

        // For each feature, try candidate thresholds
        for f in 0..<dim {
            let values = features.map { $0[f] }
            let sorted = Set(values).sorted()

            // Candidate thresholds: midpoints between unique sorted values
            for t in 0..<(sorted.count - 1) {
                let threshold = (sorted[t] + sorted[t + 1]) / 2.0

                var aboveCount = 0.0
                var abovePositive = 0.0
                var belowCount = 0.0
                var belowPositive = 0.0

                for i in 0..<n {
                    if features[i][f] > threshold {
                        aboveCount += 1
                        abovePositive += labels[i]
                    } else {
                        belowCount += 1
                        belowPositive += labels[i]
                    }
                }

                guard aboveCount > 0, belowCount > 0 else { continue }

                let aboveRate = abovePositive / aboveCount
                let belowRate = belowPositive / belowCount

                let aboveEntropy = binaryEntropy(aboveRate)
                let belowEntropy = binaryEntropy(belowRate)

                let weightedEntropy = (aboveCount / Double(n)) * aboveEntropy
                    + (belowCount / Double(n)) * belowEntropy
                let gain = baseEntropy - weightedEntropy

                if gain > bestGain {
                    bestGain = gain
                    bestFeatureIdx = f
                    bestThreshold = threshold
                    bestAboveRate = aboveRate
                    bestBelowRate = belowRate
                }
            }
        }

        return DecisionTreeModel(
            featureIndex: bestFeatureIdx, threshold: bestThreshold,
            baseConflictRate: baseRate,
            aboveThresholdRate: bestAboveRate, belowThresholdRate: bestBelowRate,
            sampleCount: n
        )
    }

    /// Binary entropy: -p*log2(p) - (1-p)*log2(1-p)
    private static func binaryEntropy(_ p: Double) -> Double {
        if p <= 0 || p >= 1 { return 0 }
        return -(p * log2(p) + (1 - p) * log2(1 - p))
    }
}

// MARK: - MLTrainer

/// On-device ML trainer that improves orchestration intelligence over time.
/// Runs after each orchestration, trains from local LearningRecord data.
/// No cloud, no external deps -- pure Swift math.
actor MLTrainer {

    private let logger = Logger(subsystem: "com.xroads", category: "MLTrainer")
    private let learningRepository: LearningRepository

    // Trained model weights (persisted to .crossroads/ml/)
    private var storyTimeModel: LinearRegressionModel?
    private var complexityClassifier: NaiveBayesClassifier?
    private var conflictPredictor: DecisionTreeModel?

    /// Directory where model files are persisted.
    private let modelDirectory: URL

    init(learningRepository: LearningRepository, repoPath: URL? = nil) {
        self.learningRepository = learningRepository

        let base = repoPath ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.modelDirectory = base
            .appendingPathComponent(".crossroads")
            .appendingPathComponent("ml")
    }

    // MARK: - Initialization

    /// Load persisted models from disk if they exist.
    func loadModels() {
        storyTimeModel = loadJSON(filename: "time_model.json")
        complexityClassifier = loadJSON(filename: "category_model.json")
        conflictPredictor = loadJSON(filename: "conflict_model.json")

        let loaded = [
            storyTimeModel != nil ? "time" : nil,
            complexityClassifier != nil ? "category" : nil,
            conflictPredictor != nil ? "conflict" : nil
        ].compactMap { $0 }

        if !loaded.isEmpty {
            logger.info("Loaded ML models: \(loaded.joined(separator: ", "))")
        } else {
            logger.info("No persisted ML models found, will train from data")
        }
    }

    // MARK: - Training Pipeline

    /// Train all models from accumulated LearningRecord data.
    /// Requires at least 10 records to produce meaningful models.
    func trainAll() async throws {
        let records = try await learningRepository.fetchAllRecords()
        guard records.count >= 10 else {
            logger.info("Not enough data to train (\(records.count) records, need 10+)")
            return
        }

        trainTimeEstimator(from: records)
        trainCategorizer(from: records)
        trainConflictPredictor(from: records)

        try saveModels()
        logger.info("ML models trained from \(records.count) records")
    }

    // MARK: - Time Estimation Training

    /// Train linear regression model: predict durationMs from story features.
    private func trainTimeEstimator(from records: [LearningRecord]) {
        // Filter to successful records with positive duration
        let valid = records.filter { $0.success && $0.durationMs > 0 }
        guard valid.count >= 6 else {
            logger.info("Not enough valid records for time model (\(valid.count), need 6+)")
            return
        }

        let features = valid.map { StoryFeatures(from: $0).regressionVector }
        let targets = valid.map { Double($0.durationMs) }

        if let model = LinearRegressionModel.train(features: features, targets: targets) {
            storyTimeModel = model
            logger.info("Time estimator trained: \(model.sampleCount) samples, \(model.weights.count) weights")
        } else {
            logger.warning("Time estimator training failed (singular matrix or insufficient data)")
        }
    }

    // MARK: - Categorizer Training

    /// Train Naive Bayes classifier: predict task category from title + file patterns.
    private func trainCategorizer(from records: [LearningRecord]) {
        // Build labeled documents from records
        // Use the existing LearningEngine categorization logic as ground truth
        let documents: [(title: String, filePatterns: [String], category: String)] = records.compactMap { record in
            let extensions = StoryFeatures.extractExtensions(from: record.filePatterns)
            let patterns: [String]
            if let data = record.filePatterns.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                patterns = decoded
            } else {
                patterns = []
            }
            guard !patterns.isEmpty || !record.storyTitle.isEmpty else { return nil }

            // Derive category from file patterns using the same rules as LearningEngine
            let category = deriveCategory(title: record.storyTitle, filePatterns: patterns)
            return (title: record.storyTitle, filePatterns: patterns, category: category)
        }

        guard documents.count >= 5 else {
            logger.info("Not enough documents for category model (\(documents.count), need 5+)")
            return
        }

        let model = NaiveBayesClassifier.train(documents: documents)
        complexityClassifier = model
        logger.info("Categorizer trained: \(model.totalDocuments) documents, vocabulary \(model.vocabularySize)")
    }

    /// Derive category from file patterns (mirrors LearningEngine.categorizeStory logic).
    private func deriveCategory(title: String, filePatterns: [String]) -> String {
        let lowerTitle = title.lowercased()
        let allPatterns = filePatterns.joined(separator: " ").lowercased()
        let combined = lowerTitle + " " + allPatterns

        if filePatterns.contains(where: { p in
            let l = p.lowercased()
            return l.hasSuffix(".rs") || l.hasSuffix(".toml")
        }) { return "backend_rust" }

        if filePatterns.contains(where: { p in
            let l = p.lowercased()
            return l.hasSuffix(".ts") || l.hasSuffix(".tsx")
        }) { return "frontend_react" }

        if filePatterns.contains(where: { $0.lowercased().hasSuffix(".swift") }) {
            return "ios_swift"
        }

        if combined.contains("test") { return "testing" }

        if filePatterns.contains(where: { $0.lowercased().hasSuffix(".sql") }) {
            return "db_migration"
        }

        if filePatterns.contains(where: { p in
            let l = p.lowercased()
            return l.hasSuffix(".yml") || l.hasSuffix(".yaml")
        }) { return "devops" }

        if filePatterns.contains(where: { $0.lowercased().hasSuffix(".md") }) {
            return "docs"
        }

        return "general"
    }

    // MARK: - Conflict Predictor Training

    /// Train decision stump: predict whether two concurrent stories will conflict.
    /// Generates training pairs from historical records in the same session.
    private func trainConflictPredictor(from records: [LearningRecord]) {
        // Group records by session to find concurrent stories
        let bySession = Dictionary(grouping: records, by: \.sessionId)

        var features: [[Double]] = []
        var labels: [Double] = []

        for (_, sessionRecords) in bySession where sessionRecords.count >= 2 {
            // Generate pairs within session
            for i in 0..<sessionRecords.count {
                for j in (i + 1)..<sessionRecords.count {
                    let a = sessionRecords[i]
                    let b = sessionRecords[j]

                    let patternsA = parseFilePatterns(a.filePatterns)
                    let patternsB = parseFilePatterns(b.filePatterns)

                    let overlapCount = computeFileOverlap(patternsA, patternsB)
                    let dirOverlap = computeDirectoryOverlap(patternsA, patternsB)
                    let extMatch = computeExtensionMatch(patternsA, patternsB)
                    let historicalRate = Double(a.conflictsEncountered + b.conflictsEncountered) > 0 ? 1.0 : 0.0

                    features.append([
                        Double(overlapCount),
                        dirOverlap,
                        extMatch,
                        historicalRate
                    ])

                    // Label: did either story actually encounter conflicts?
                    let hadConflict = (a.conflictsEncountered > 0 || b.conflictsEncountered > 0) ? 1.0 : 0.0
                    labels.append(hadConflict)
                }
            }
        }

        guard features.count >= 5 else {
            logger.info("Not enough conflict pairs for training (\(features.count), need 5+)")
            return
        }

        if let model = DecisionTreeModel.train(features: features, labels: labels) {
            conflictPredictor = model
            let featureName = model.featureIndex < DecisionTreeModel.featureNames.count
                ? DecisionTreeModel.featureNames[model.featureIndex]
                : "feature_\(model.featureIndex)"
            logger.info("Conflict predictor trained: split on \(featureName) > \(String(format: "%.2f", model.threshold)), \(model.sampleCount) pairs")
        }
    }

    // MARK: - Conflict Feature Extraction

    private func parseFilePatterns(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let patterns = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return patterns
    }

    /// Count exact file path overlaps between two pattern sets.
    private func computeFileOverlap(_ a: [String], _ b: [String]) -> Int {
        let setA = Set(a.map { $0.lowercased() })
        let setB = Set(b.map { $0.lowercased() })
        return setA.intersection(setB).count
    }

    /// Fraction of shared directories between two pattern sets (0.0 - 1.0).
    private func computeDirectoryOverlap(_ a: [String], _ b: [String]) -> Double {
        let dirsA = Set(a.compactMap { path -> String? in
            let components = path.lowercased().split(separator: "/")
            return components.count > 1 ? String(components.dropLast().joined(separator: "/")) : nil
        })
        let dirsB = Set(b.compactMap { path -> String? in
            let components = path.lowercased().split(separator: "/")
            return components.count > 1 ? String(components.dropLast().joined(separator: "/")) : nil
        })
        let union = dirsA.union(dirsB)
        guard !union.isEmpty else { return 0 }
        return Double(dirsA.intersection(dirsB).count) / Double(union.count)
    }

    /// Fraction of shared file extensions (Jaccard similarity, 0.0 - 1.0).
    private func computeExtensionMatch(_ a: [String], _ b: [String]) -> Double {
        let extsA = Set(a.compactMap { path -> String? in
            let ext = (path as NSString).pathExtension.lowercased()
            return ext.isEmpty ? nil : ext
        })
        let extsB = Set(b.compactMap { path -> String? in
            let ext = (path as NSString).pathExtension.lowercased()
            return ext.isEmpty ? nil : ext
        })
        let union = extsA.union(extsB)
        guard !union.isEmpty else { return 0 }
        return Double(extsA.intersection(extsB).count) / Double(union.count)
    }

    // MARK: - Prediction API (called by LearningEngine)

    /// Predict story completion time in seconds from features.
    /// Returns nil if model is not trained yet (caller falls back to heuristics).
    func predictStoryTime(features: StoryFeatures) -> TimeInterval? {
        guard let model = storyTimeModel else { return nil }
        let ms = model.predict(features: features.regressionVector)
        return ms / 1000.0 // Convert ms to seconds
    }

    /// Classify a story into a task category from title and file patterns.
    /// Returns nil if classifier is not trained yet.
    func classifyStory(title: String, filePatterns: [String]) -> String? {
        guard let model = complexityClassifier else { return nil }
        return model.classify(title: title, filePatterns: filePatterns)
    }

    /// Predict conflict risk between two stories (0.0 = safe, 1.0 = certain conflict).
    /// Returns nil if predictor is not trained yet.
    func predictConflictRisk(storyA: StoryFeatures, storyB: StoryFeatures) -> Double? {
        guard let model = conflictPredictor else { return nil }

        let patternsA = storyA.fileExtensions.map { "file.\($0)" }
        let patternsB = storyB.fileExtensions.map { "file.\($0)" }

        let overlapCount = computeFileOverlap(patternsA, patternsB)
        let dirOverlap = computeDirectoryOverlap(patternsA, patternsB)
        let extMatch = computeExtensionMatch(patternsA, patternsB)
        // No historical data available at prediction time for new story pairs
        let historicalRate = 0.0

        let featureVector = [Double(overlapCount), dirOverlap, extMatch, historicalRate]
        return model.predict(features: featureVector)
    }

    // MARK: - Persistence

    /// Save all trained models to .crossroads/ml/ as JSON.
    private func saveModels() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: modelDirectory.path) {
            try fm.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }

        if let model = storyTimeModel {
            try saveJSON(model, filename: "time_model.json")
        }
        if let model = complexityClassifier {
            try saveJSON(model, filename: "category_model.json")
        }
        if let model = conflictPredictor {
            try saveJSON(model, filename: "conflict_model.json")
        }

        // Ensure .crossroads is in .gitignore
        ensureGitignore()
    }

    private func saveJSON<T: Encodable>(_ value: T, filename: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let path = modelDirectory.appendingPathComponent(filename)
        try data.write(to: path, options: .atomic)
        logger.debug("Saved model to \(path.path)")
    }

    private func loadJSON<T: Decodable>(filename: String) -> T? {
        let path = modelDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Make sure .crossroads/ is in .gitignore (idempotent).
    private func ensureGitignore() {
        let repoRoot = modelDirectory
            .deletingLastPathComponent()  // .crossroads
            .deletingLastPathComponent()  // repo root
        let gitignorePath = repoRoot.appendingPathComponent(".gitignore")

        let entry = ".crossroads/"
        if let contents = try? String(contentsOf: gitignorePath, encoding: .utf8) {
            if contents.contains(entry) { return }
            let updated = contents.hasSuffix("\n")
                ? contents + entry + "\n"
                : contents + "\n" + entry + "\n"
            try? updated.write(to: gitignorePath, atomically: true, encoding: .utf8)
        } else {
            try? (entry + "\n").write(to: gitignorePath, atomically: true, encoding: .utf8)
        }
    }
}
