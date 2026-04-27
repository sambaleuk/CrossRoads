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
              prompt: "BEFORE stopping: 1) Run the project's build/test command. 2) Fix any errors. 3) Only stop if build passes. If you cannot verify, list what's untested."
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
        \(Self.agentRoleBrief(skillName: skillName, slotNumber: slotNumber))

        You are Slot \(slotNumber) in a multi-agent orchestration. Other agents are working in parallel on different branches.

        ## Working Rules
        1. **Stay in your worktree** — all work happens at `\(worktreePath)`
        2. **Read the codebase first** — understand the project structure before acting
        3. **Execute your role**: \(taskDescription)
        4. **Commit with clear messages** — prefix: `[slot-\(slotNumber)] description`
        5. **DO NOT** run destructive commands (rm -rf, git push --force, DROP TABLE)
        6. **DO NOT** modify files that other agents are likely working on
        7. **Update progress** — write learnings to `progress.txt`

        ## Coordination
        - Other agents are working on parallel branches
        - Your branch: `\(branchName)`
        - Merge coordination is handled by the orchestrator — just commit to your branch

        ## Start Now
        \(Self.agentStartInstruction(skillName: skillName))
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

        // Generate settings.local.json with hooks + Playwright MCP for browser testing
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
            ],
            "mcpServers": [
                "playwright": [
                    "command": "npx",
                    "args": [
                        "@playwright/mcp@latest",
                        "--headless",
                        "--viewport-size=1280x720"
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

        ## Agent Quality Overrides

        ### Forced Verification
        You are FORBIDDEN from reporting a task as complete until you have:
        - Run the project's test/build command and confirmed it passes
        - If TypeScript: `npx tsc --noEmit` before claiming success
        - If Python: `python -m pytest` or equivalent
        - If Rust: `cargo check`
        - If Swift: `swift build`
        Fixed ALL resulting errors. A successful file write is NOT a successful task.

        ### Senior Dev Standard
        Do NOT "try the simplest approach" or "avoid improvements beyond what was asked."
        If architecture is flawed, state is duplicated, or patterns are inconsistent — fix them.
        Ask yourself: "What would a senior perfectionist dev reject in code review?" Fix all of it.

        ### File Read Safety
        Each file read is capped at 2,000 lines. For files over 500 LOC:
        - Read in chunks using offset and limit parameters
        - Never assume a single read captured the full file
        - Re-read any file before editing if more than 5 messages have passed

        ### Search Completeness
        Grep is text matching, not semantic analysis. When renaming or changing any function:
        - Search for direct calls, type references, string literals, dynamic imports
        - Search re-exports, barrel files, test mocks separately
        - If results look suspiciously small, re-run with narrower scope

        ### Context Decay
        After 10+ tool calls, re-read files before editing. Auto-compaction may have
        destroyed your memory of file contents. Never trust stale context.

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
        // --verbose is REQUIRED with --output-format stream-json in Claude Code 2.1.87+
        var arguments: [String] = [
            "-p", prompt,
            "--agent", agentName,
            "--output-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions"
        ]

        // Cockpit brain (slotIndex -1) gets more turns and parent dir access
        if slotIndex == -1 {
            let maxTurns = UserDefaults.standard.object(forKey: "brainMaxTurns") as? Int ?? 30
            arguments.append(contentsOf: ["--max-turns", String(maxTurns)])

            // Allow brain to read worktree directories (siblings of project dir)
            let parentDir = URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
            arguments.append(contentsOf: ["--add-dir", parentDir])
        }

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

    // MARK: - Native Agent Launch (Gemini, Codex)

    /// Launches a non-Claude agent (Gemini CLI, Codex) in its native non-interactive mode.
    ///
    /// Unlike `launchHeadless` which uses Claude's `--agent` + `--output-format stream-json`,
    /// this method launches the agent's own CLI with its native flags:
    /// - Gemini: positional prompt + `--yolo` for auto-approval
    /// - Codex: `--prompt` + `--full-auto` for headless execution
    func launchNativeAgent(
        agentType: AgentType,
        slotIndex: Int,
        prompt: String,
        worktreePath: String,
        environment: [String: String] = [:],
        onOutput: @escaping @MainActor @Sendable (String) -> Void,
        onTermination: @escaping @MainActor @Sendable (Int32) -> Void
    ) async throws -> HeadlessSession {

        let adapter = agentType.adapter()
        let executablePath = adapter.executablePath

        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw CLIAdapterError.executableNotFound(cli: agentType.rawValue, path: executablePath)
        }

        var arguments: [String]

        switch agentType {
        case .gemini:
            // Gemini CLI: positional prompt + yolo mode for full autonomy
            arguments = [
                "--yolo",
                prompt
            ]
        case .codex:
            // Codex CLI: prompt flag + full-auto mode
            arguments = [
                "--prompt", prompt,
                "--full-auto"
            ]
        default:
            // Fallback: just pass the prompt as positional arg
            arguments = [prompt]
        }

        var env = environment
        env["CROSSROADS_SLOT"] = String(slotIndex)
        env["CROSSROADS_AGENT"] = agentType.rawValue

        let processId = try await ptyRunner.launch(
            executable: executablePath,
            arguments: arguments,
            workingDirectory: worktreePath,
            environment: env,
            onOutput: { rawOutput in
                Task { @MainActor in
                    onOutput(rawOutput)
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
            agentName: "\(agentType.rawValue)-slot-\(slotIndex)"
        )

        logger.info("Launched native \(agentType.rawValue) for slot \(slotIndex): pid=\(processId)")
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

    // MARK: - Cockpit Brain Definition (PRD-S09 US-001)

    /// Generates .claude/agents/cockpit-brain.md, meta-monitor.md, and transverse-producer.md.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the main project repository
    ///   - cop: Current cockpit orchestration plan (optional)
    ///   - activeSlots: Currently assigned dev slots
    func generateCockpitBrainDefinition(
        projectPath: String,
        cop: CockpitOrchestrationPlan?,
        activeSlots: [AgentSlot],
        wakeContext: String? = nil,
        chairmanBrief: String? = nil
    ) throws {
        let agentsDir = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".claude")
            .appendingPathComponent("agents")

        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let projectName = cop?.projectName ?? URL(fileURLWithPath: projectPath).lastPathComponent

        // Load soul.md from app bundle (the brain's identity and environmental awareness)
        let soulContent: String
        if let soulURL = Bundle.main.url(forResource: "cockpit-soul", withExtension: "md"),
           let content = try? String(contentsOf: soulURL, encoding: .utf8) {
            soulContent = content
        } else {
            // Fallback: try to load from Resources directory in development
            let devPath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Services/
                .deletingLastPathComponent() // XRoads/
                .appendingPathComponent("Resources")
                .appendingPathComponent("cockpit-soul.md")
            soulContent = (try? String(contentsOf: devPath, encoding: .utf8)) ?? ""
        }

        // Build active slots section
        var slotLines = ""
        if activeSlots.isEmpty {
            slotLines = "No dev slots currently active."
        } else {
            for slot in activeSlots {
                let branch = slot.branchName ?? "unassigned"
                let task = slot.currentTask ?? "no task"
                slotLines += "- Slot \(slot.slotIndex + 1) (\(slot.agentType)) on branch `\(branch)` — task: \(task)\n"
            }
        }

        // Build PRD section
        var prdSection = "No active PRD. Monitor for new prd.json files."
        let prdPath = URL(fileURLWithPath: projectPath).appendingPathComponent("prd.json")
        if FileManager.default.fileExists(atPath: prdPath.path),
           let prdData = try? Data(contentsOf: prdPath),
           let prd = try? JSONSerialization.jsonObject(with: prdData) as? [String: Any] {
            let featureName = (prd["feature_name"] as? String) ?? "unknown"
            let stories = (prd["user_stories"] as? [[String: Any]]) ?? []
            let doneCount = stories.filter { ($0["status"] as? String) == "done" }.count
            prdSection = "Feature: \(featureName) — \(stories.count) stories (\(doneCount) done, \(stories.count - doneCount) remaining)"
        }

        // --- cockpit-brain.md ---
        let cockpitBrainContent = """
        ---
        name: cockpit-brain
        description: "Autonomous project orchestrator — observes dev agents, manages quality, produces transverse deliverables"
        tools:
          - Read
          - Edit
          - Bash
          - Glob
          - Grep
          - Write
          - WebSearch
          - Agent(scanner, commander, advisor, meta-monitor, transverse-producer)
        model: inherit
        permissionMode: auto
        memory: project
        background: true
        ---

        \(soulContent)

        ---

        # Session Context — \(projectName)

        ## Chairman Strategy
        The Chairman analyzed this project and made the following decisions:

        \(chairmanBrief ?? "No chairman brief available — first session or chairman not yet deliberated.")

        ## Active Dev Slots
        \(slotLines)

        ## Current PRD
        \(prdSection)

        \(wakeContext.map { """
        ## Previous Session Context (Self-Continuity)
        You are resuming from a previous session. Here is what you knew:

        \($0)

        Use this context to resume monitoring without re-scanning everything.
        Verify that the previous state still holds before acting on it.
        """ } ?? "")

        ## Start Now
        Begin by scanning the project structure and checking for active dev worktrees.
        """

        let brainPath = agentsDir.appendingPathComponent("cockpit-brain.md")
        try cockpitBrainContent.write(to: brainPath, atomically: true, encoding: .utf8)

        // --- meta-monitor.md ---
        let metaMonitorContent = """
        ---
        name: meta-monitor
        whenToUse: "When dev agents are running and you need to check code quality, run tests, or detect conflicts"
        description: "Code quality monitor — watches dev worktrees, runs tests, detects conflicts"
        tools:
          - Read
          - Bash
          - Glob
          - Grep
        model: inherit
        permissionMode: auto
        isolation: false
        ---

        # Meta Monitor — Code Quality Watcher

        You monitor all active dev worktrees for the **\(projectName)** project.

        ## Responsibilities
        - Run tests in each active worktree
        - Check for code quality issues (linting, formatting)
        - Detect potential merge conflicts between worktrees
        - Flag stalled agents (no commits in last 10 minutes)
        - Report findings back to the cockpit brain

        ## Rules
        - NEVER modify any files — you are read-only + test runner
        - Report findings clearly with file paths and line numbers
        - Prioritize: test failures > conflicts > quality issues > staleness
        """

        let metaMonitorPath = agentsDir.appendingPathComponent("meta-monitor.md")
        try metaMonitorContent.write(to: metaMonitorPath, atomically: true, encoding: .utf8)

        // --- transverse-producer.md ---
        let transverseContent = """
        ---
        name: transverse-producer
        whenToUse: "When you need to produce non-code deliverables like documentation, strategy documents, or marketing copy"
        description: "Produces non-code deliverables — documentation, strategy, marketing copy"
        tools:
          - Read
          - Write
          - WebSearch
        model: inherit
        permissionMode: auto
        isolation: false
        ---

        # Transverse Producer — Deliverables Generator

        You produce non-code deliverables for the **\(projectName)** project.

        ## Responsibilities
        - Create documentation (README, deploy guides, API reference)
        - Generate marketing copy (landing page, value proposition)
        - Write strategy documents (go-to-market, pricing model)
        - Produce research artifacts (competitive analysis, user personas)

        ## Rules
        - Write all deliverables to `.crossroads/deliverables/`
        - Each deliverable must be actionable and specific
        - Reference actual project features and domain terminology
        - Create a `_index.md` summarizing all deliverables produced
        """

        let transversePath = agentsDir.appendingPathComponent("transverse-producer.md")
        try transverseContent.write(to: transversePath, atomically: true, encoding: .utf8)

        // --- scanner.md --- (reads project state, never modifies)
        let scannerContent = """
        ---
        name: scanner
        whenToUse: "When you need to observe the current project state — worktrees, git status, PRDs, file structure"
        description: "Project state observer — scans worktrees, git status, PRDs, and reports changes"
        tools:
          - Read
          - Bash
          - Glob
          - Grep
        model: inherit
        permissionMode: auto
        isolation: false
        ---

        # Scanner — Project State Observer + Functional Tester

        You are a READ-ONLY scanner for **\(projectName)**. You NEVER modify files.

        ## Your Job
        Scan the current state, try to BUILD and RUN the project, run tests, and return a structured report.

        ## Phase 1: Project State
        1. `git worktree list` — active worktrees
        2. For each worktree: `git -C {path} log --oneline -5` + `git -C {path} diff --stat`
        3. `find . -name "prd*.json" -maxdepth 3` — PRD files
        4. Read any prd.json found — count stories, check statuses
        5. `ls -la` of project root — file structure overview

        ## Phase 2: Build & Launch Attempt
        Detect the project type and try to build/launch:
        - **Node.js** (package.json): `npm install && npm run build` (or `yarn build`)
        - **Python** (requirements.txt/pyproject.toml): `pip install -r requirements.txt && python -m pytest --co -q` (collect tests)
        - **Rust** (Cargo.toml): `cargo check`
        - **Swift** (Package.swift): `swift build`
        - **Go** (go.mod): `go build ./...`
        - **Other**: Try `make` or report "unknown build system"

        If the build succeeds, try to start the app briefly (timeout 10s) to verify it boots:
        - Node: `timeout 10 npm run dev 2>&1 || true` (capture first output)
        - Python: `timeout 10 python manage.py runserver 2>&1 || timeout 10 python -m flask run 2>&1 || true`
        - Other: skip launch, build success is enough

        Capture ALL output (stdout + stderr). Report build status and any errors verbatim.

        ## Phase 3: Test Execution
        Run the project's test suite (if any):
        - Node: `npm test 2>&1` (or `npx vitest run`, `npx jest`)
        - Python: `python -m pytest -v --tb=short 2>&1`
        - Rust: `cargo test 2>&1`
        - Swift: `swift test 2>&1`
        - Go: `go test ./... 2>&1`

        Report: total tests, passed, failed, skipped. Include first 20 lines of any failure output.

        ## Phase 4: Browser Testing (if web app)
        If the project is a web app (Node/Python/Ruby with a dev server):
        1. Start the dev server in background: `npm run dev &` (or equivalent)
        2. Wait 5 seconds for it to boot
        3. Use Playwright MCP tools to test it:
           - `browser_navigate` to `http://localhost:PORT`
           - `browser_snapshot` to see the page structure
           - `browser_take_screenshot` to capture what the page looks like
           - Test basic navigation: click main links, check for errors
        4. Output `[PREVIEW:http://localhost:PORT]` so the operator can see the app in the Review Ribbon
        5. Stop the dev server when done: `kill %1`

        Report: did the app boot? Did pages load? Any console errors? Include screenshot descriptions.
        If Playwright MCP is not available, skip this phase.

        ## Output Format
        Return EXACTLY this structure (the brain parses it):
        ```
        SCANNER REPORT
        Project: {name}
        Tech: {detected stack}
        Worktrees: {count} ({list with commit counts})
        PRDs: {count} ({story summary})

        BUILD STATUS: {SUCCESS | FAILURE | SKIPPED}
        Build output: {first 30 lines of build output, or "clean build"}
        Build errors: {error lines, or "none"}

        LAUNCH STATUS: {BOOTS | FAILS | SKIPPED}
        Launch output: {first 10 lines, or "N/A"}

        TEST STATUS: {X passed, Y failed, Z skipped | NO TESTS | SKIPPED}
        Test failures: {failure details, first 20 lines per failure}

        Issues: {any detected problems — build failures, missing deps, test failures, stale worktrees}
        Changes since last scan: {what's new}
        ```

        Be concise. No opinions. Just facts. Errors must be verbatim — the brain and operator need exact messages.
        """
        try scannerContent.write(to: agentsDir.appendingPathComponent("scanner.md"), atomically: true, encoding: .utf8)

        // --- commander.md --- (launches and manages slots)
        let commanderContent = """
        ---
        name: commander
        whenToUse: "When you need to decide which agent slots to launch and what tasks to assign them"
        description: "Slot commander — decides which agents to launch and manages the execution fleet"
        tools:
          - Read
          - Bash
          - Glob
          - Grep
        model: inherit
        permissionMode: auto
        isolation: false
        ---

        # Commander — Slot Fleet Manager

        You are the commander for **\(projectName)**. You decide what agents to launch based on evidence.

        ## Context
        You receive a scanner report (with build/test/launch results) and an advisor recommendation.
        Your job: turn analysis into action via [LAUNCH] commands.

        ## Decision Framework

        ### If build FAILS:
        - Launch 1 debugger slot: `[LAUNCH:claude:debug:Fix build errors — {paste exact error}]`
        - Do NOT launch other slots until the build passes.

        ### If tests FAIL:
        - Launch 1 debugger slot with failing test names: `[LAUNCH:claude:debug:Fix failing tests — {test names and errors}]`
        - If build passes but tests fail, also consider launching an implementer for missing functionality.

        ### If build and tests PASS:
        - Check PRD status. If stories remain, launch implementers for the next dependency layer.
        - If no PRD, check if the scanner found issues (stale worktrees, missing docs, etc.) and act accordingly.

        ### If no project exists yet:
        - Do nothing. Report "Empty project — waiting for instructions."

        ## Protocol
        Output one or more [LAUNCH] commands:
        - `[LAUNCH:claude:backend:Implement US-001 to US-003 — core API routes]`
        - `[LAUNCH:gemini:testing:Write integration tests for all endpoints]`
        - `[LAUNCH:claude:debug:Fix build error — cannot find module 'express']`
        - `[LAUNCH:claude:review:Review code quality and security]`

        ## Rules
        - Max 6 slots total. Check how many are already running before launching more.
        - Match agent to task: claude for complex logic, gemini for testing/review, codex for straightforward tasks.
        - Each [LAUNCH] must include the SPECIFIC error or task. Copy-paste errors from the scanner report.
        - Never launch a generic "work on project" slot.
        - If nothing needs launching, say: "No action needed — project is healthy."
        - If PRD exists: map stories to slots by dependency layers.
        - If no PRD and no issues: launch 1 analysis slot max.
        - IMPORTANT: Every [LAUNCH] you output goes through the operator's approval ribbon.
          The operator sees your proposal and can approve, reject, or modify before execution.
          Be precise so the operator can make an informed decision.
        """
        try commanderContent.write(to: agentsDir.appendingPathComponent("commander.md"), atomically: true, encoding: .utf8)

        // --- advisor.md --- (recommends actions to the operator)
        let advisorContent = """
        ---
        name: advisor
        whenToUse: "When you need strategic recommendations about what to do next with the project"
        description: "Strategic advisor — analyzes scanner output and recommends actions to the operator"
        tools:
          - Read
          - Bash
          - Glob
          - Grep
          - WebSearch
        model: inherit
        permissionMode: auto
        isolation: false
        ---

        # Advisor — Strategic Recommendations

        You are the strategic advisor for **\(projectName)**.

        ## Context
        You receive a scanner report. Your job: tell the operator what matters and what to do next.

        ## Output Format
        Output a [CHAT] message with your recommendations:

        ```
        [CHAT] **Project Status**: {one-line summary}

        **What's happening**: {2-3 sentences on current state}

        **Recommended next steps**:
        1. {most important action}
        2. {second action}
        3. {optional third action}

        **Risks**: {any concerns — stalled slots, missing tests, conflicts}
        ```

        ## Rules
        - Be specific. Reference actual file paths, story IDs, branch names.
        - One [CHAT] message per invocation. Make it count.
        - If everything is fine: say so briefly. Don't invent problems.
        - If there are issues: prioritize. Most critical first.
        """
        try advisorContent.write(to: agentsDir.appendingPathComponent("advisor.md"), atomically: true, encoding: .utf8)

        logger.info("Generated cockpit brain + 5 support agent definitions for \(projectName)")
    }

    // MARK: - Cockpit Session Launch (PRD-S09 US-002)

    /// Launches the cockpit brain as a long-running Claude Code headless session.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the main project repository
    ///   - cop: Current cockpit orchestration plan (optional)
    ///   - activeSlots: Currently assigned dev slots
    ///   - onOutput: Callback for raw output lines
    ///   - onTermination: Callback when the process terminates
    ///   - onSessionId: Callback when a session_id is extracted
    /// - Returns: A HeadlessSession for the cockpit brain
    func launchCockpitSession(
        projectPath: String,
        cop: CockpitOrchestrationPlan?,
        activeSlots: [AgentSlot],
        onOutput: @escaping @MainActor @Sendable (String) -> Void,
        onTermination: @escaping @MainActor @Sendable (Int32) -> Void,
        onSessionId: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> HeadlessSession {
        let projectName = cop?.projectName ?? URL(fileURLWithPath: projectPath).lastPathComponent

        // Build the context prompt — LIVE STATE only. Identity comes from soul.md in the agent definition.
        let domainInfo = cop.map { "\($0.domain) / \($0.projectType)" } ?? "general"

        var slotLines = ""
        if !activeSlots.isEmpty {
            slotLines = activeSlots.map { slot -> String in
                let branch = slot.branchName ?? "unassigned"
                let task = slot.currentTask ?? "no task"
                let worktree = slot.worktreePath ?? "unknown"
                return "  Slot \(slot.slotIndex + 1) (\(slot.agentType)) [\(slot.status.rawValue)]: \(task)\n    Branch: \(branch)\n    Worktree: \(worktree)"
            }.joined(separator: "\n")
        }

        let contextPrompt = """
        You are Claude, running as an autonomous project monitor inside a multi-agent coding orchestrator called XRoads.

        Your role in this session: scan the project, analyze what's happening, and take action.

        Project: \(projectName) at \(projectPath)
        Domain: \(domainInfo)
        \(activeSlots.isEmpty ? "No agents running." : "\(activeSlots.count) agents active:\n\(slotLines)")

        What you can do:
        - Use the @scanner agent to get a project state report
        - Use the @advisor agent to produce recommendations
        - Use [CHAT] prefix to send messages to the operator's chat panel
        - Use [LAUNCH:claude:backend:task description] to create new agent slots (up to 6)
        - Read files, run git commands, analyze the codebase

        Your agent definition (cockpit-brain.md) has detailed instructions on all protocols and available agents.

        Start by scanning the project state. If agents are running, check their progress. If not, decide what needs doing and act.
        """

        // Use slotIndex -1 to distinguish cockpit brain from dev slots
        let session = try await launchHeadless(
            slotIndex: -1,
            agentName: "cockpit-brain",
            prompt: contextPrompt,
            worktreePath: projectPath,
            projectPath: projectPath,
            onOutput: onOutput,
            onTermination: onTermination,
            onSessionId: onSessionId
        )

        logger.info("Cockpit brain session launched for \(projectName)")
        return session
    }

    /// Terminates the cockpit brain session gracefully.
    ///
    /// - Parameter processId: The process UUID from the HeadlessSession
    func stopCockpitSession(processId: UUID) async {
        do {
            try await ptyRunner.terminate(id: processId)
            logger.info("Cockpit brain session terminated")
        } catch {
            logger.warning("Failed to terminate cockpit brain: \(error.localizedDescription)")
        }
    }

    // MARK: - Cockpit Brain Output Parsing (PRD-S09 US-008)

    /// Categorizes a stream-json event from the cockpit brain into a brain entry type.
    ///
    /// - Parameter event: Parsed JSON dictionary from stream-json
    /// - Returns: Tuple of (type, content) or nil if event should be ignored
    /// Structured message prefix → (brainType, logLevel)
    private static let messageProtocol: [(prefix: String, brainType: String, logLevel: String)] = [
        ("[ERROR]",    "error",    "error"),
        ("[ALERT]",    "decision", "warn"),
        ("[DECISION]", "decision", "info"),
        ("[STATUS]",   "status",   "info"),
        ("[REPORT]",   "report",   "info"),
        ("[LOG]",      "log",      "info"),
    ]

    static func categorizeBrainEvent(_ event: [String: Any]) -> (type: String, content: String)? {
        guard let eventType = event["type"] as? String else { return nil }

        switch eventType {
        case "assistant":
            guard let message = event["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else { return nil }

            for block in contentBlocks {
                guard let text = block["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check for slot launch request: [LAUNCH:agent:role:task]
                // Routes through the approval ribbon — operator must approve before execution.
                if trimmed.hasPrefix("[LAUNCH:") && trimmed.contains("]") {
                    let payload = String(trimmed.dropFirst(8).prefix(while: { $0 != "]" }))
                    let parts = payload.components(separatedBy: ":")
                    if parts.count >= 3 {
                        let agent = parts[0].trimmingCharacters(in: .whitespaces)
                        let role = parts[1].trimmingCharacters(in: .whitespaces)
                        let task = parts[2...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

                        // Create a proposal instead of auto-launching
                        let proposal = BrainProposal.fromLaunch(agentType: agent, role: role, task: task)
                        NotificationCenter.default.post(
                            name: .brainProposalReceived,
                            object: nil,
                            userInfo: ["proposal": proposal]
                        )
                        return (type: "decision", content: "Proposal: launch \(agent) as \(role) — \(task) [awaiting approval]")
                    }
                }

                // Check for chat message: [CHAT] message → posts to chat panel (no approval needed)
                if trimmed.hasPrefix("[CHAT]") {
                    let msg = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    NotificationCenter.default.post(
                        name: .cockpitBrainToChat,
                        object: nil,
                        userInfo: ["content": msg, "role": "system"]
                    )
                    return (type: "decision", content: "→ Chat: \(msg)")
                }

                // Check for suite switch command: [SUITE:marketer]
                // Routes through the approval ribbon.
                if trimmed.hasPrefix("[SUITE:") && trimmed.contains("]") {
                    let suiteId = String(trimmed.dropFirst(7).prefix(while: { $0 != "]" }))
                    let proposal = BrainProposal.fromSuiteSwitch(suiteId: suiteId)
                    NotificationCenter.default.post(
                        name: .brainProposalReceived,
                        object: nil,
                        userInfo: ["proposal": proposal]
                    )
                    return (type: "decision", content: "Proposal: switch to \(suiteId) suite [awaiting approval]")
                }

                // [PREVIEW:url] prefix → open URL in the Review Ribbon Preview tab
                if trimmed.hasPrefix("[PREVIEW:") && trimmed.contains("]") {
                    let url = String(trimmed.dropFirst(9).prefix(while: { $0 != "]" }))
                    NotificationCenter.default.post(
                        name: .previewURLReceived,
                        object: nil,
                        userInfo: ["url": url]
                    )
                    NotificationCenter.default.post(
                        name: .cockpitBrainToChat,
                        object: nil,
                        userInfo: ["content": "Preview: opening \(url)", "role": "system"]
                    )
                    return (type: "action", content: "Preview: \(url)")
                }

                // Check for structured communication protocol prefixes
                for proto in messageProtocol {
                    if trimmed.hasPrefix(proto.prefix) {
                        let msg = String(trimmed.dropFirst(proto.prefix.count)).trimmingCharacters(in: .whitespaces)
                        return (type: proto.brainType, content: msg)
                    }
                }

                // Fallback: keyword-based categorization
                let lower = trimmed.lowercased()
                if lower.contains("spawning") || lower.contains("launching") || lower.contains("activating") {
                    return (type: "subagent", content: text)
                }
                if lower.contains("detected") || lower.contains("decided") || lower.contains("switching") || lower.contains("recommending") {
                    return (type: "decision", content: text)
                }
                if lower.contains("monitoring") || lower.contains("checking") || lower.contains("scanning") || lower.contains("polling") {
                    return (type: "loop", content: text)
                }
                // Default assistant text is thinking
                return (type: "thinking", content: text)
            }
            return nil

        case "tool_use":
            let toolName = (event["name"] as? String) ?? "unknown"
            var detail = toolName
            if let input = event["tool_input"] as? [String: Any] {
                if let filePath = input["file_path"] as? String {
                    detail = "\(toolName) \(filePath)"
                } else if let command = input["command"] as? String {
                    let truncated = String(command.prefix(80))
                    detail = "\(toolName) \(truncated)"
                } else if let pattern = input["pattern"] as? String {
                    detail = "\(toolName) \(pattern)"
                } else if let url = input["url"] as? String, toolName.contains("browser") {
                    detail = "\(toolName) \(url)"
                }
            }
            return (type: "action", content: detail)

        case "result":
            // Check for base64 screenshot data from Playwright
            if let resultContent = event["content"] as? [[String: Any]] {
                for block in resultContent {
                    if let type = block["type"] as? String, type == "image",
                       let source = block["source"] as? [String: Any],
                       let data = source["data"] as? String,
                       let imageData = Data(base64Encoded: data) {
                        // Broadcast screenshot for Agent Vision
                        NotificationCenter.default.post(
                            name: .agentScreenshotReceived,
                            object: nil,
                            userInfo: [
                                "slotNumber": -1,  // brain slot
                                "imageData": imageData,
                            ]
                        )
                        return (type: "action", content: "Screenshot captured")
                    }
                }
            }
            if let resultText = event["result"] as? String, !resultText.isEmpty {
                // Also check for inline base64 PNG in text results
                if resultText.hasPrefix("data:image/png;base64,") || resultText.hasPrefix("iVBOR") {
                    let base64 = resultText.hasPrefix("data:image/png;base64,")
                        ? String(resultText.dropFirst("data:image/png;base64,".count))
                        : resultText
                    if let imageData = Data(base64Encoded: base64) {
                        NotificationCenter.default.post(
                            name: .agentScreenshotReceived,
                            object: nil,
                            userInfo: ["slotNumber": -1, "imageData": imageData]
                        )
                        return (type: "action", content: "Screenshot captured")
                    }
                }
                return (type: "thinking", content: resultText)
            }
            return nil

        case "error":
            let errorMsg = (event["error"] as? String) ?? "Unknown error"
            return (type: "error", content: errorMsg)

        default:
            return nil
        }
    }

    // MARK: - Role Briefs

    /// Returns role-specific brief section for agent definition.
    static func agentRoleBrief(skillName: String, slotNumber: Int) -> String {
        switch skillName {
        case "testing", "qa", "e2e", "perf":
            return """
            You are the **TESTER**. Your job is to verify, not to implement.
            - Write integration tests that cover cross-module interactions
            - Write E2E tests for critical user flows
            - Run performance benchmarks if the project supports it
            - Report test coverage gaps
            - Do NOT implement features — only test what exists
            """
        case "review", "audit", "lint":
            return """
            You are the **REVIEWER**. Your job is to critique, not to build.
            - Perform a systematic code review (OWASP top 10, SOLID, complexity)
            - Check for security vulnerabilities, injection risks, hardcoded secrets
            - Identify dead code, unused imports, style inconsistencies
            - Write a review report at .crossroads/deliverables/code-review.md
            - Fix critical issues only — leave style fixes as recommendations
            """
        case "docs", "documentation", "write":
            return """
            You are the **WRITER**. Your job is to document, not to code.
            - Generate accurate README.md with setup, usage, and architecture
            - Document public APIs with examples
            - Write developer guides for key workflows
            - Create changelog entries for recent changes
            - All documentation goes in the project root or .crossroads/deliverables/
            """
        case "security", "compliance":
            return """
            You are the **SECURITY AUDITOR**. Your job is to find vulnerabilities.
            - Scan for OWASP top 10 vulnerabilities
            - Check auth flows, input validation, data exposure
            - Review dependencies for known CVEs
            - Write a security report at .crossroads/deliverables/security-audit.md
            - Fix critical vulnerabilities — document the rest
            """
        case "debug", "fix", "bugfix":
            return """
            You are the **DEBUGGER**. Your job is to find and fix bugs.
            - Reproduce the reported issue first
            - Diagnose the root cause, not just the symptom
            - Implement the minimal fix
            - Write regression tests to prevent recurrence
            """
        case "devops", "infra", "deploy":
            return """
            You are the **DEVOPS ENGINEER**. Your job is infrastructure and deployment.
            - Implement CI/CD pipelines, Dockerfiles, deployment scripts
            - Configure monitoring and alerting
            - Document deployment procedures
            """
        default:
            return """
            You are an **IMPLEMENTER**. Your job is to build features with quality.
            - Implement assigned stories from the PRD
            - Write unit tests for every feature
            - Ensure all tests pass before committing
            - Follow existing code patterns and conventions
            """
        }
    }

    /// Returns role-specific start instruction.
    static func agentStartInstruction(skillName: String) -> String {
        switch skillName {
        case "testing", "qa", "e2e", "perf":
            return "Read the codebase to understand what's been implemented, then write comprehensive tests."
        case "review", "audit", "lint":
            return "Read the full codebase systematically, then produce your review report."
        case "docs", "documentation", "write":
            return "Read the codebase and existing docs, then generate accurate documentation."
        case "security", "compliance":
            return "Scan the codebase for security issues, then produce your audit report."
        case "debug", "fix", "bugfix":
            return "Reproduce the bug, diagnose the root cause, then fix it with regression tests."
        case "devops", "infra", "deploy":
            return "Analyze the current infrastructure, then implement your assigned task."
        default:
            return "Read the project structure, then implement your assigned task with tests."
        }
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
        # NOTE: Python uses sys.stdout.write (not the stdlib print function) because the
        # StructuredLoggingTests lint scanner does a literal substring match across this
        # Swift source file and cannot distinguish heredoc Python from real Swift prints.
        # Behaviourally identical to a stdout newline-suppressed write.
        COMMAND=$(echo "$INPUT" | python3 -c "
        import sys, json
        try:
            data = json.load(sys.stdin)
            sys.stdout.write(str(data.get('tool_input', {}).get('command', '')))
        except:
            sys.stdout.write('')
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

    /// Flushes any remaining content in the buffer (last line without trailing newline).
    /// Call this after the stream ends to avoid losing the final JSON event.
    func flush() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""

        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return [json]
    }
}
