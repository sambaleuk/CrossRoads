import Foundation
import GRDB
import os

// MARK: - CockpitDatabaseManager

/// Manages the SQLite database for cockpit session persistence.
/// Handles schema creation and versioned migrations.
actor CockpitDatabaseManager {

    private let logger = Logger(subsystem: "com.xroads", category: "CockpitDB")

    /// The GRDB database queue (thread-safe access)
    let dbQueue: DatabaseQueue

    /// Initialize with a file path for persistent storage
    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
        try migrator.migrate(dbQueue)
        let dbPath = path
        logger.info("CockpitDB initialized at \(dbPath)")
    }

    /// Initialize with an in-memory database (for testing)
    init() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(configuration: config)
        try migrator.migrate(dbQueue)
        logger.info("CockpitDB initialized in-memory")
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_cockpit_tables") { db in
            // CockpitSession table
            try db.create(table: "cockpit_session") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectPath", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "idle")
                t.column("chairmanBrief", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Unique index: one active session per project_path
            // (active = not closed)
            try db.create(
                index: "idx_cockpit_session_project_active",
                on: "cockpit_session",
                columns: ["projectPath", "status"],
                unique: true,
                condition: Column("status") != "closed"
            )

            // AgentSlot table with FK to CockpitSession
            try db.create(table: "agent_slot") { t in
                t.primaryKey("id", .text).notNull()
                t.column("cockpitSessionId", .text)
                    .notNull()
                    .references("cockpit_session", onDelete: .cascade)
                t.column("slotIndex", .integer).notNull()
                t.column("status", .text).notNull().defaults(to: "empty")
                t.column("agentType", .text).notNull()
                t.column("worktreePath", .text)
                t.column("branchName", .text)
                t.column("skillId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes from model.json
            try db.create(
                index: "idx_agent_slot_slot_index",
                on: "agent_slot",
                columns: ["slotIndex"]
            )
            try db.create(
                index: "idx_agent_slot_status",
                on: "agent_slot",
                columns: ["status"]
            )
        }

        migrator.registerMigration("v2_create_metier_skill") { db in
            // MetierSkill table
            try db.create(table: "metier_skill") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("family", .text).notNull()
                t.column("skillMdPath", .text).notNull()
                t.column("requiredMcps", .text)
                t.column("description", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Unique index on name (from model.json)
            try db.create(
                index: "idx_metier_skill_name",
                on: "metier_skill",
                columns: ["name"],
                unique: true
            )

            // Index on family (from model.json)
            try db.create(
                index: "idx_metier_skill_family",
                on: "metier_skill",
                columns: ["family"]
            )
        }

        migrator.registerMigration("v3_create_agent_message") { db in
            // AgentMessage table with FK to AgentSlot (emitted_by, cascade delete)
            try db.create(table: "agent_message") { t in
                t.primaryKey("id", .text).notNull()
                t.column("content", .text).notNull()
                t.column("messageType", .text).notNull()
                t.column("fromSlotId", .text)
                    .notNull()
                    .references("agent_slot", onDelete: .cascade)
                t.column("toSlotId", .text)
                    .references("agent_slot", onDelete: .cascade)
                t.column("isBroadcast", .boolean).notNull().defaults(to: false)
                t.column("readAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }

            // Indexes from model.json
            try db.create(
                index: "idx_agent_message_from_slot",
                on: "agent_message",
                columns: ["fromSlotId"]
            )
            try db.create(
                index: "idx_agent_message_to_slot",
                on: "agent_message",
                columns: ["toSlotId"]
            )
            try db.create(
                index: "idx_agent_message_created_at",
                on: "agent_message",
                columns: ["createdAt"]
            )
        }

        migrator.registerMigration("v4_add_agent_slot_current_task") { db in
            try db.alter(table: "agent_slot") { t in
                t.add(column: "currentTask", .text)
            }
        }

        migrator.registerMigration("v5_create_execution_gate") { db in
            // ExecutionGate table with FK to AgentSlot (triggered_by, cascade delete)
            try db.create(table: "execution_gate") { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentSlotId", .text)
                    .notNull()
                    .references("agent_slot", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("operationType", .text).notNull()
                t.column("operationPayload", .text).notNull()
                t.column("riskLevel", .text).notNull()
                t.column("estimatedImpact", .text)
                t.column("approvedBy", .text)
                t.column("approvedAt", .datetime)
                t.column("deniedReason", .text)
                t.column("rollbackPayload", .text)
                t.column("auditEntry", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes from model.json
            try db.create(
                index: "idx_execution_gate_status",
                on: "execution_gate",
                columns: ["status"]
            )
            try db.create(
                index: "idx_execution_gate_risk_level",
                on: "execution_gate",
                columns: ["riskLevel"]
            )
            try db.create(
                index: "idx_execution_gate_created_at",
                on: "execution_gate",
                columns: ["createdAt"]
            )
        }

        migrator.registerMigration("v6_create_cost_event") { db in
            try db.create(table: "cost_event") { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentSlotId", .text)
                    .notNull()
                    .references("agent_slot", onDelete: .cascade)
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("inputTokens", .integer).notNull()
                t.column("outputTokens", .integer).notNull()
                t.column("costCents", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_cost_event_slot",
                on: "cost_event",
                columns: ["agentSlotId"]
            )
            try db.create(
                index: "idx_cost_event_created_at",
                on: "cost_event",
                columns: ["createdAt"]
            )
        }

        migrator.registerMigration("v7_create_org_role") { db in
            try db.create(table: "org_role") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text)
                    .notNull()
                    .references("cockpit_session", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("roleType", .text).notNull()
                t.column("parentRoleId", .text)
                    .references("org_role", onDelete: .setNull)
                t.column("assignedSlotId", .text)
                    .references("agent_slot", onDelete: .setNull)
                t.column("goalDescription", .text)
                t.column("skillNames", .text)
                t.column("authority", .text).notNull().defaults(to: "limited")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_org_role_session",
                on: "org_role",
                columns: ["sessionId"]
            )
            try db.create(
                index: "idx_org_role_parent",
                on: "org_role",
                columns: ["parentRoleId"]
            )
        }

        migrator.registerMigration("v8_create_budget_tables") { db in
            try db.create(table: "budget_config") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text)
                    .notNull()
                    .references("cockpit_session", onDelete: .cascade)
                t.column("slotId", .text)
                    .references("agent_slot", onDelete: .cascade)
                t.column("budgetCents", .integer).notNull().defaults(to: 2500)
                t.column("warningThresholdPct", .integer).notNull().defaults(to: 80)
                t.column("hardStopEnabled", .boolean).notNull().defaults(to: true)
                t.column("throttleEnabled", .boolean).notNull().defaults(to: true)
                t.column("dailyLimitCents", .integer)
                t.column("perStoryLimitCents", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_budget_config_session",
                on: "budget_config",
                columns: ["sessionId"]
            )

            try db.create(table: "budget_alert") { t in
                t.primaryKey("id", .text).notNull()
                t.column("budgetConfigId", .text)
                    .notNull()
                    .references("budget_config", onDelete: .cascade)
                t.column("alertType", .text).notNull()
                t.column("currentSpendCents", .integer).notNull()
                t.column("budgetCents", .integer).notNull()
                t.column("percentUsed", .double).notNull()
                t.column("message", .text).notNull()
                t.column("acknowledged", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_budget_alert_config",
                on: "budget_alert",
                columns: ["budgetConfigId"]
            )
            try db.create(
                index: "idx_budget_alert_acknowledged",
                on: "budget_alert",
                columns: ["acknowledged"]
            )
        }

        migrator.registerMigration("v9_create_heartbeat_config") { db in
            try db.create(table: "heartbeat_config") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text)
                    .notNull()
                    .references("cockpit_session", onDelete: .cascade)
                t.column("slotId", .text)
                    .references("agent_slot", onDelete: .cascade)
                t.column("intervalMs", .integer).notNull().defaults(to: 30000)
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("lastPulseAt", .datetime)
                t.column("lastPulseResult", .text)
                t.column("consecutiveFailures", .integer).notNull().defaults(to: 0)
                t.column("maxFailures", .integer).notNull().defaults(to: 5)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_heartbeat_config_session",
                on: "heartbeat_config",
                columns: ["sessionId"]
            )
        }

        migrator.registerMigration("v10_create_scheduled_run") { db in
            try db.create(table: "scheduled_run") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectPath", .text).notNull()
                t.column("prdPath", .text).notNull()
                t.column("cronExpression", .text)
                t.column("triggerType", .text).notNull().defaults(to: "manual")
                t.column("triggerConfig", .text)
                t.column("roleTemplateName", .text)
                t.column("budgetPreset", .text)
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("lastRunAt", .datetime)
                t.column("lastRunResult", .text)
                t.column("nextRunAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_scheduled_run_enabled",
                on: "scheduled_run",
                columns: ["enabled"]
            )
            try db.create(
                index: "idx_scheduled_run_next_run",
                on: "scheduled_run",
                columns: ["nextRunAt"]
            )
        }

        migrator.registerMigration("v11_create_workspace_and_runtime") { db in
            try db.create(table: "workspace") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("projectPath", .text).notNull()
                t.column("color", .text).notNull().defaults(to: "#0DF170")
                t.column("icon", .text)
                t.column("isActive", .boolean).notNull().defaults(to: false)
                t.column("maxSlots", .integer).notNull().defaults(to: 6)
                t.column("totalBudgetCents", .integer)
                t.column("metadata", .text)
                t.column("lastAccessedAt", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_workspace_project_path",
                on: "workspace",
                columns: ["projectPath"]
            )

            try db.create(table: "agent_runtime") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("runtimeType", .text).notNull().defaults(to: "cli")
                t.column("command", .text)
                t.column("url", .text)
                t.column("dockerImage", .text)
                t.column("healthCheckCommand", .text)
                t.column("configSchema", .text)
                t.column("configDefaults", .text)
                t.column("capabilities", .text).notNull().defaults(to: "[]")
                t.column("icon", .text)
                t.column("color", .text)
                t.column("isBuiltin", .boolean).notNull().defaults(to: false)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_agent_runtime_name",
                on: "agent_runtime",
                columns: ["name"],
                unique: true
            )
        }

        migrator.registerMigration("v12_create_config_snapshot") { db in
            try db.create(table: "config_snapshot") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text)
                    .references("cockpit_session", onDelete: .setNull)
                t.column("workspaceId", .text)
                    .references("workspace", onDelete: .setNull)
                t.column("configType", .text).notNull()
                t.column("version", .integer).notNull()
                t.column("data", .text).notNull()
                t.column("diff", .text)
                t.column("changedBy", .text).notNull().defaults(to: "system")
                t.column("changeReason", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_config_snapshot_type_version",
                on: "config_snapshot",
                columns: ["configType", "version"]
            )
            try db.create(
                index: "idx_config_snapshot_session",
                on: "config_snapshot",
                columns: ["sessionId"]
            )
        }

        migrator.registerMigration("v13_create_learning_tables") { db in
            try db.create(table: "learning_record") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text)
                    .notNull()
                    .references("cockpit_session", onDelete: .cascade)
                t.column("storyId", .text).notNull()
                t.column("storyTitle", .text).notNull()
                t.column("storyComplexity", .text).notNull().defaults(to: "moderate")
                t.column("agentType", .text).notNull()
                t.column("runtimeId", .text)
                    .references("agent_runtime", onDelete: .setNull)
                t.column("model", .text)
                t.column("durationMs", .integer).notNull()
                t.column("costCents", .integer).notNull()
                t.column("filesChanged", .integer).notNull()
                t.column("linesAdded", .integer).notNull()
                t.column("linesRemoved", .integer).notNull()
                t.column("testsRun", .integer).notNull()
                t.column("testsPassed", .integer).notNull()
                t.column("testsFailed", .integer).notNull()
                t.column("conflictsEncountered", .integer).notNull()
                t.column("retriesNeeded", .integer).notNull()
                t.column("success", .boolean).notNull()
                t.column("failureReason", .text)
                t.column("filePatterns", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_learning_record_session",
                on: "learning_record",
                columns: ["sessionId"]
            )
            try db.create(
                index: "idx_learning_record_agent_type",
                on: "learning_record",
                columns: ["agentType"]
            )
            try db.create(
                index: "idx_learning_record_story",
                on: "learning_record",
                columns: ["storyId"]
            )

            try db.create(table: "performance_profile") { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentType", .text).notNull()
                t.column("runtimeId", .text)
                    .references("agent_runtime", onDelete: .setNull)
                t.column("taskCategory", .text).notNull()
                t.column("totalExecutions", .integer).notNull()
                t.column("successRate", .double).notNull()
                t.column("avgDurationMs", .integer).notNull()
                t.column("avgCostCents", .integer).notNull()
                t.column("avgFilesChanged", .double).notNull()
                t.column("avgTestPassRate", .double).notNull()
                t.column("conflictRate", .double).notNull()
                t.column("lastUpdatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_performance_profile_agent_category",
                on: "performance_profile",
                columns: ["agentType", "taskCategory"],
                unique: true
            )
        }

        return migrator
    }

    /// Path to the default cockpit database file
    static func defaultPath() throws -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("XRoads")

        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        return appSupport.appendingPathComponent("cockpit.sqlite").path
    }
}
