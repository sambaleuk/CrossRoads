import Foundation
import os

// MARK: - HeadlessSession

/// Represents an active Claude Code headless session launched by the orchestrator.
struct HeadlessSession: Sendable {
    let processId: UUID
    let slotIndex: Int
    let agentName: String
}

// MARK: - ClaudeCodeOrchestrator

/// Replaces manual PTY spawning with Claude Code native orchestration features.
///
/// Generates subagent definitions (.claude/agents/), hooks configuration,
/// project context (CLAUDE.md + rules), and launches Claude Code in headless mode
/// with structured stream-json output.
///
/// PRD-S08: Claude Code Native Orchestration
actor ClaudeCodeOrchestrator {

    private let logger = Logger(subsystem: "com.xroads", category: "ClaudeCodeOrch")
    private let ptyRunner: PTYProcessRunner

    init(ptyRunner: PTYProcessRunner) {
        self.ptyRunner = ptyRunner
    }

    // MARK: - Agent Definition Generation (US-001)

    /// Generates a .claude/agents/slot-{N}-{skill}.md subagent definition file.
    ///
    /// Each file configures Claude Code's native subagent system with worktree isolation,
    /// auto permission mode, background execution, and a Stop hook for test verification.
    ///
    /// - Parameters:
    ///   - slot: The agent slot to generate a definition for
    ///   - chairmanBrief: The chairman's orchestration brief
    ///   - projectPath: Path to the main project repository
    /// - Returns: The file path where the agent definition was written
    @discardableResult
    func generateAgentDefinition(
        slot: AgentSlot,
        chairmanBrief: String,
        projectPath: String
    ) throws -> String {
        let slotNumber = slot.slotIndex + 1
        let skillName = deriveSkillName(from: slot)
        let taskDescription = slot.currentTask ?? "Implement assigned stories"
        let agentType = slot.agentType
        let branchName = slot.branchName ?? "xroads/slot-\(slotNumber)"
        let worktreePath = slot.worktreePath ?? projectPath
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent

        // Scope tools by role
        let tools = toolsForRole(agentType: agentType, taskDescription: taskDescription)
        let toolsYaml = tools.map { "  - \($0)" }.joined(separator: "\n")

        let content = """
        ---
        name: slot-\(slotNumber)-\(skillName)
        description: "\(escapeYaml(taskDescription))"
        tools:
        \(toolsYaml)
        model: inherit
        permissionMode: auto
        isolation: worktree
        memory: project
        background: true
        hooks:
          Stop:
            - type: prompt
              prompt: "Have all assigned tasks been completed with passing tests? If not, list remaining work."
        ---

        # Agent Brief — Slot \(slotNumber) [\(agentType)]

        ## Mission
        \(taskDescription)

        ## Project Context
        - **Project**: \(projectName)
        - **Branch**: `\(branchName)`
        - **Agent**: \(agentType)
        - **Worktree**: `\(worktreePath)`
        - **Main Repo**: `\(projectPath)`

        ## Chairman Brief
        \(chairmanBrief)

        ## Your Role
        You are Slot \(slotNumber) in a multi-agent orchestration. Other agents are working in parallel on different branches. DO NOT touch files outside your assigned scope.

        ## Working Rules
        1. **Stay in your worktree** — all work happens at `\(worktreePath)`
        2. **Read the codebase first** — understand the project structure before writing code
        3. **Implement your assigned task**: \(taskDescription)
        4. **Write tests** for every feature you implement
        5. **Run tests** and ensure they pass before committing
        6. **Commit with clear messages** — prefix with your slot: `[slot-\(slotNumber)] description`
        7. **DO NOT** run destructive commands (rm -rf, git push --force, DROP TABLE)
        8. **DO NOT** modify files that other agents are likely working on
        9. **Update progress** — write learnings to `progress.txt`

        ## Coordination
        - Other agents are working on parallel branches
        - Your branch: `\(branchName)`
        - Merge coordination is handled by the orchestrator — just commit to your branch
        - If you encounter a blocker, write it to `progress.txt`

        ## Start Now
        Begin by reading the project structure, then implement your assigned task with tests.
        """

        // Write to .claude/agents/ directory
        let agentsDir = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".claude")
            .appendingPathComponent("agents")

        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let fileName = "slot-\(slotNumber)-\(skillName).md"
        let filePath = agentsDir.appendingPathComponent(fileName)
        try content.write(to: filePath, atomically: true, encoding: .utf8)

        logger.info("Generated agent definition: \(fileName)")
        return filePath.path
    }

    // MARK: - Hooks Configuration (US-003)

    /// Generates .claude/settings.local.json with hooks for safety and quality gates.
    ///
    /// Configures:
    /// - PreToolUse hook on Bash: runs safe-executor.sh to block dangerous commands
    /// - Stop hook: verification prompt to ensure all tasks are complete with passing tests
    ///
    /// - Parameter projectPath: Path to the main project repository
    func generateHooksConfig(projectPath: String) throws {
        let claudeDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")

        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        // Generate safe-executor.sh
        let safeExecutorScript = generateSafeExecutorScript()
        let scriptPath = hooksDir.appendingPathComponent("safe-executor.sh")
        try safeExecutorScript.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.path
        )

        // Generate settings.local.json
        let settings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            [
                                "type": "command",
                                "command": "bash \(scriptPath.path)"
                            ]
                        ]
                    ]
                ],
                "Stop": [
                    [
                        "hooks": [
                            [
                                "type": "prompt",
                                "prompt": "Verify: are all assigned tasks complete with passing tests? List any remaining work."
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let settingsData = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let settingsPath = claudeDir.appendingPathComponent("settings.local.json")
        try settingsData.write(to: settingsPath)

        logger.info("Generated hooks config at \(settingsPath.path)")
    }

    // MARK: - Project Context Generation (US-004)

    /// Generates/updates .claude/CLAUDE.md and .claude/rules/ for orchestration context.
    ///
    /// CLAUDE.md provides project-level context that all agents inherit.
    /// Rules are path-scoped files that load only when agents work on matching paths.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the main project repository
    ///   - cop: The cockpit orchestration plan (optional)
    ///   - chairmanBrief: The chairman's orchestration brief
    func generateProjectContext(
        projectPath: String,
        cop: CockpitOrchestrationPlan?,
        chairmanBrief: String
    ) throws {
        let claudeDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let projectName = cop?.projectName ?? URL(fileURLWithPath: projectPath).lastPathComponent
        let domain = cop?.domain ?? "general"

        let claudeMd = """
        # XRoads Orchestration Context

        ## Project
        \(projectName) — \(domain)

        ## Orchestration Rules
        - Commit with prefix: [slot-{N}] description
        - Stay in your assigned worktree
        - Do NOT modify files outside your scope
        - Run tests before committing
        - Write learnings to progress.txt

        ## Chairman Brief
        \(chairmanBrief)

        @prd.json
        """

        let claudeMdPath = claudeDir.appendingPathComponent("CLAUDE.md")

        // Only write if doesn't exist or is an XRoads-generated file (check for our header)
        if let existing = try? String(contentsOf: claudeMdPath, encoding: .utf8),
           !existing.contains("# XRoads Orchestration Context") {
            // Existing non-XRoads CLAUDE.md — append our context
            let merged = existing + "\n\n" + claudeMd
            try merged.write(to: claudeMdPath, atomically: true, encoding: .utf8)
        } else {
            try claudeMd.write(to: claudeMdPath, atomically: true, encoding: .utf8)
        }

        // Generate path-scoped rules
        try generateRulesFiles(projectPath: projectPath)

        logger.info("Generated project context for \(projectName)")
    }

    // MARK: - Headless Launch (US-002)

    /// Launches Claude Code in headless mode for a given slot.
    ///
    /// Uses `claude -p "<prompt>" --agent <agentName> --output-format stream-json`
    /// to run autonomously, streaming structured JSON events (text, tool_use, session_id).
    ///
    /// - Parameters:
    ///   - slotIndex: The slot index (0-based)
    ///   - agentName: Name of the agent definition (e.g. "slot-1-backend")
    ///   - prompt: The task prompt for the agent
    ///   - worktreePath: Path to the git worktree
    ///   - projectPath: Path to the main project repository
    ///   - sessionId: Optional Claude session ID for resume
    ///   - environment: Additional environment variables
    ///   - onOutput: Callback for raw output lines
    ///   - onTermination: Callback when the process terminates
    ///   - onSessionId: Callback when a session_id is extracted from the stream
    /// - Returns: A HeadlessSession with the process ID
    func launchHeadless(
        slotIndex: Int,
        agentName: String,
        prompt: String,
        worktreePath: String,
        projectPath: String,
        sessionId: String? = nil,
        environment: [String: String] = [:],
        onOutput: @escaping @MainActor @Sendable (String) -> Void,
        onTermination: @escaping @MainActor @Sendable (Int32) -> Void,
        onSessionId: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> HeadlessSession {

        // Find claude binary
        let claudePath = ClaudeAdapter().executablePath

        guard FileManager.default.fileExists(atPath: claudePath) else {
            throw CLIAdapterError.executableNotFound(cli: "claude", path: claudePath)
        }

        // Build arguments for headless mode
        var arguments: [String] = [
            "-p", prompt,
            "--agent", agentName,
            "--output-format", "stream-json"
        ]

        // Resume support: use --resume if we have a previous session ID
        if let sessionId, !sessionId.isEmpty {
            arguments.append(contentsOf: ["--resume", sessionId])
        }

        // Merge environment
        var env = environment
        env["CROSSROADS_SLOT"] = String(slotIndex)
        env["CROSSROADS_AGENT"] = "claude"

        // Buffer for partial JSON lines from the stream
        let jsonBuffer = JSONLineBuffer()

        let processId = try await ptyRunner.launch(
            executable: claudePath,
            arguments: arguments,
            workingDirectory: worktreePath,
            environment: env,
            onOutput: { [jsonBuffer, logger] rawOutput in
                // Forward raw output for terminal display
                Task { @MainActor in
                    onOutput(rawOutput)
                }

                // Parse stream-json events
                let events = jsonBuffer.append(rawOutput)
                for event in events {
                    Self.processStreamEvent(
                        event,
                        slotIndex: slotIndex,
                        logger: logger,
                        onOutput: onOutput,
                        onSessionId: onSessionId
                    )
                }
            },
            onTermination: { exitCode in
                Task { @MainActor in
                    onTermination(exitCode)
                }
            }
        )

        let session = HeadlessSession(
            processId: processId,
            slotIndex: slotIndex,
            agentName: agentName
        )

        logger.info("Launched headless session for slot \(slotIndex): agent=\(agentName), pid=\(processId)")
        return session
    }

    // MARK: - Memory Injection (US-005)

    /// Injects initial performance memories into an agent's memory directory.
    ///
    /// Reads from PerformanceProfile data and writes to
    /// .claude/agents/slot-{N}/MEMORY.md so the agent starts with historical context.
    ///
    /// - Parameters:
    ///   - slotIndex: The slot index (0-based)
    ///   - agentType: The agent type string
    ///   - projectPath: Path to the main project repository
    ///   - profiles: Performance profiles to inject (from LearningRepository)
    func injectInitialMemories(
        slotIndex: Int,
        agentType: String,
        projectPath: String,
        profiles: [PerformanceProfile]
    ) throws {
        let slotNumber = slotIndex + 1
        let agentMemDir = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".claude")
            .appendingPathComponent("agents")
            .appendingPathComponent("slot-\(slotNumber)")

        try FileManager.default.createDirectory(at: agentMemDir, withIntermediateDirectories: true)

        var memoryContent = "# Agent Memory\n\n"
        memoryContent += "## Performance History\n"

        if profiles.isEmpty {
            memoryContent += "- No previous execution data available\n"
        } else {
            for profile in profiles {
                let successPct = Int(profile.successRate * 100)
                memoryContent += "- \(profile.taskCategory): \(successPct)% success rate (\(profile.totalExecutions) executions)\n"
            }
        }

        memoryContent += "\n## Session Notes\n"
        memoryContent += "- Agent type: \(agentType)\n"
        memoryContent += "- Slot: \(slotNumber)\n"
        memoryContent += "- Initialized: \(ISO8601DateFormatter().string(from: Date()))\n"

        let memoryPath = agentMemDir.appendingPathComponent("MEMORY.md")
        try memoryContent.write(to: memoryPath, atomically: true, encoding: .utf8)

        logger.info("Injected initial memories for slot \(slotNumber)")
    }

    // MARK: - Private Helpers

    /// Derives a short skill name from the slot's agent type and task.
    private func deriveSkillName(from slot: AgentSlot) -> String {
        let task = (slot.currentTask ?? "general").lowercased()

        if task.contains("backend") || task.contains("api") || task.contains("server") || task.contains("rust") {
            return "backend"
        } else if task.contains("frontend") || task.contains("ui") || task.contains("react") || task.contains("view") {
            return "frontend"
        } else if task.contains("test") || task.contains("spec") || task.contains("qa") {
            return "testing"
        } else if task.contains("doc") || task.contains("readme") {
            return "docs"
        } else if task.contains("deploy") || task.contains("ci") || task.contains("infra") {
            return "devops"
        }

        return "general"
    }

    /// Returns the list of tools appropriate for a given role.
    private func toolsForRole(agentType: String, taskDescription: String) -> [String] {
        let baseTool = ["Read", "Edit", "Bash", "Glob", "Grep", "Write"]
        // All roles get the same tools for now; can be scoped later per US-001
        return baseTool
    }

    /// Escapes a string for safe inclusion in YAML.
    private func escapeYaml(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Generates .claude/rules/ with path-scoped rule files.
    private func generateRulesFiles(projectPath: String) throws {
        let rulesDir = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".claude")
            .appendingPathComponent("rules")

        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)

        // Backend rules
        let backendRules = """
        ---
        path: src/api/**,models/**,services/**,src-tauri/**
        ---

        # Backend Rules

        - Follow existing Rust/Swift patterns in the codebase
        - All API endpoints must have error handling
        - Database queries must use parameterized statements
        - Run `cargo test` or `swift test` before committing
        - Never expose internal errors to API consumers
        """

        let backendPath = rulesDir.appendingPathComponent("backend.md")
        if !FileManager.default.fileExists(atPath: backendPath.path) {
            try backendRules.write(to: backendPath, atomically: true, encoding: .utf8)
        }

        // Frontend rules
        let frontendRules = """
        ---
        path: src/components/**,src/views/**,src/pages/**
        ---

        # Frontend Rules

        - Use existing component patterns and naming conventions
        - Keep components small and focused
        - Use TypeScript strict mode
        - Extract reusable logic into hooks
        - Test user interactions, not implementation details
        """

        let frontendPath = rulesDir.appendingPathComponent("frontend.md")
        if !FileManager.default.fileExists(atPath: frontendPath.path) {
            try frontendRules.write(to: frontendPath, atomically: true, encoding: .utf8)
        }

        // Testing rules
        let testingRules = """
        ---
        path: tests/**,spec/**,__tests__/**
        ---

        # Testing Rules

        - Follow existing test patterns in the codebase
        - One assertion per test when possible
        - Use descriptive test names that explain the expected behavior
        - Mock external dependencies, not internal modules
        - Test edge cases and error paths
        """

        let testingPath = rulesDir.appendingPathComponent("testing.md")
        if !FileManager.default.fileExists(atPath: testingPath.path) {
            try testingRules.write(to: testingPath, atomically: true, encoding: .utf8)
        }
    }

    /// Generates the safe-executor.sh hook script content.
    private func generateSafeExecutorScript() -> String {
        return """
        #!/usr/bin/env bash
        # XRoads SafeExecutor Hook — blocks dangerous commands
        # Reads tool input from stdin (JSON), checks for dangerous patterns.
        # Exit 0 = allow, Exit 2 = block

        INPUT=$(cat)
        COMMAND=$(echo "$INPUT" | python3 -c "
        import sys, json
        try:
            data = json.load(sys.stdin)
            print(data.get('tool_input', {}).get('command', ''))
        except:
            print('')
        " 2>/dev/null)

        # Dangerous patterns to block
        PATTERNS=(
            "rm -rf /"
            "rm -rf ~"
            "rm -rf ."
            "DROP TABLE"
            "DROP DATABASE"
            "TRUNCATE TABLE"
            "git push --force"
            "git push -f"
            "git reset --hard"
            "git clean -fd"
            "git checkout -- ."
            "chmod -R 777"
            "> /dev/sda"
        )

        for pattern in "${PATTERNS[@]}"; do
            if echo "$COMMAND" | grep -qiF "$pattern"; then
                echo "BLOCKED by XRoads SafeExecutor: dangerous pattern detected: $pattern" >&2
                exit 2
            fi
        done

        exit 0
        """
    }

    /// Processes a single parsed stream-json event from Claude Code headless output.
    @Sendable
    private static func processStreamEvent(
        _ event: [String: Any],
        slotIndex: Int,
        logger: Logger,
        onOutput: @escaping @MainActor @Sendable (String) -> Void,
        onSessionId: @escaping @MainActor @Sendable (String) -> Void
    ) {
        // Extract event type
        guard let type = event["type"] as? String else { return }

        switch type {
        case "assistant":
            // Text content from the assistant
            if let message = event["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        Task { @MainActor in
                            onOutput("[slot-\(slotIndex + 1)] \(text)\n")
                        }
                    }
                }
            }

        case "tool_use":
            // Tool call event
            if let toolName = event["name"] as? String {
                logger.debug("Slot \(slotIndex): tool_use -> \(toolName)")
            }

        case "result":
            // Session completion — may contain session_id
            if let sessionId = event["session_id"] as? String {
                Task { @MainActor in
                    onSessionId(sessionId)
                }
                logger.info("Slot \(slotIndex): captured session_id=\(sessionId)")
            }

        case "system":
            // System message — may contain session_id on init
            if let sessionId = event["session_id"] as? String {
                Task { @MainActor in
                    onSessionId(sessionId)
                }
            }

        default:
            break
        }
    }
}

// MARK: - JSONLineBuffer

/// Thread-safe buffer for accumulating partial JSON lines from a PTY stream.
/// Stream-json output may arrive in chunks that split across JSON object boundaries.
final class JSONLineBuffer: @unchecked Sendable {

    private var buffer: String = ""
    private let lock = NSLock()

    /// Appends raw text to the buffer and returns any complete JSON objects parsed.
    func append(_ text: String) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        buffer += text

        var results: [[String: Any]] = []
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            buffer = String(buffer[newlineRange.upperBound...])

            guard !line.isEmpty else { continue }

            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                results.append(json)
            }
        }

        return results
    }
}
