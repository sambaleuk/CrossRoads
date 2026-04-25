import Foundation
import GRDB

// MARK: - LearningRecord

/// Records execution metrics for a completed story.
/// Used by the learning engine to build performance profiles.
struct LearningRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionId: UUID
    var storyId: String
    var storyTitle: String
    var storyComplexity: String
    var agentType: String
    var runtimeId: UUID?
    var model: String?
    var durationMs: Int
    var costCents: Int
    var filesChanged: Int
    var linesAdded: Int
    var linesRemoved: Int
    var testsRun: Int
    var testsPassed: Int
    var testsFailed: Int
    var conflictsEncountered: Int
    var retriesNeeded: Int
    var success: Bool
    var failureReason: String?
    var filePatterns: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        storyId: String,
        storyTitle: String,
        storyComplexity: String = "moderate",
        agentType: String,
        runtimeId: UUID? = nil,
        model: String? = nil,
        durationMs: Int,
        costCents: Int,
        filesChanged: Int,
        linesAdded: Int,
        linesRemoved: Int,
        testsRun: Int,
        testsPassed: Int,
        testsFailed: Int,
        conflictsEncountered: Int,
        retriesNeeded: Int,
        success: Bool,
        failureReason: String? = nil,
        filePatterns: String = "[]",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.storyId = storyId
        self.storyTitle = storyTitle
        self.storyComplexity = storyComplexity
        self.agentType = agentType
        self.runtimeId = runtimeId
        self.model = model
        self.durationMs = durationMs
        self.costCents = costCents
        self.filesChanged = filesChanged
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.testsRun = testsRun
        self.testsPassed = testsPassed
        self.testsFailed = testsFailed
        self.conflictsEncountered = conflictsEncountered
        self.retriesNeeded = retriesNeeded
        self.success = success
        self.failureReason = failureReason
        self.filePatterns = filePatterns
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension LearningRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "learning_record"

    static let cockpitSession = belongsTo(CockpitSession.self, using: ForeignKey(["sessionId"]))
    static let agentRuntime = belongsTo(AgentRuntime.self, using: ForeignKey(["runtimeId"]))

    var cockpitSession: QueryInterfaceRequest<CockpitSession> {
        request(for: LearningRecord.cockpitSession)
    }

    var agentRuntime: QueryInterfaceRequest<AgentRuntime> {
        request(for: LearningRecord.agentRuntime)
    }

    enum Columns: String, ColumnExpression {
        case id, sessionId, storyId, storyTitle, storyComplexity
        case agentType, runtimeId, model, durationMs, costCents
        case filesChanged, linesAdded, linesRemoved
        case testsRun, testsPassed, testsFailed
        case conflictsEncountered, retriesNeeded, success
        case failureReason, filePatterns, createdAt
    }
}
