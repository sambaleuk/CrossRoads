import Foundation
import GRDB
import os

// MARK: - AgentRuntimeRepositoryError

enum AgentRuntimeRepositoryError: LocalizedError {
    case runtimeNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .runtimeNotFound(let id):
            return "AgentRuntime not found: \(id)"
        }
    }
}

// MARK: - AgentRuntimeRepository

/// Actor-based repository for AgentRuntime CRUD operations.
/// All database access is serialized through GRDB's DatabaseQueue.
actor AgentRuntimeRepository {

    private let logger = Logger(subsystem: "com.xroads", category: "AgentRuntimeRepo")
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    convenience init(databaseManager: CockpitDatabaseManager) async {
        self.init(dbQueue: await databaseManager.dbQueue)
    }

    // MARK: - Create

    /// Register a new agent runtime.
    func registerRuntime(_ runtime: AgentRuntime) throws -> AgentRuntime {
        try dbQueue.write { db in
            var record = runtime
            try record.insert(db)
            return record
        }
    }

    // MARK: - Fetch

    /// Fetch all registered runtimes.
    func fetchAll() throws -> [AgentRuntime] {
        try dbQueue.read { db in
            try AgentRuntime
                .order(AgentRuntime.Columns.name.asc)
                .fetchAll(db)
        }
    }

    /// Find a runtime by name.
    func findByName(_ name: String) throws -> AgentRuntime? {
        try dbQueue.read { db in
            try AgentRuntime
                .filter(AgentRuntime.Columns.name == name)
                .fetchOne(db)
        }
    }

    // MARK: - Register Builtins

    /// Register built-in runtimes (claude, gemini, codex) if they don't already exist.
    func registerBuiltins() throws {
        let builtins: [(name: String, command: String?, capabilities: String)] = [
            (name: "claude", command: "claude", capabilities: "[\"code\",\"review\",\"test\",\"debug\"]"),
            (name: "gemini", command: "gemini", capabilities: "[\"code\",\"review\",\"test\"]"),
            (name: "codex", command: "codex", capabilities: "[\"code\",\"test\"]")
        ]

        try dbQueue.write { db in
            for builtin in builtins {
                let existing = try AgentRuntime
                    .filter(AgentRuntime.Columns.name == builtin.name)
                    .fetchOne(db)

                if existing == nil {
                    var runtime = AgentRuntime(
                        name: builtin.name,
                        runtimeType: "cli",
                        command: builtin.command,
                        capabilities: builtin.capabilities,
                        isBuiltin: true,
                        isEnabled: true
                    )
                    try runtime.insert(db)
                    self.logger.info("Registered builtin runtime: \(builtin.name)")
                }
            }
        }
    }

    // MARK: - Update

    /// Update an existing runtime.
    func updateRuntime(_ runtime: AgentRuntime) throws -> AgentRuntime {
        try dbQueue.write { db in
            var record = runtime
            try record.update(db)
            return record
        }
    }
}
