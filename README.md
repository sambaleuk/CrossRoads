# XRoads

**Native macOS Multi-Agent AI Orchestrator**

Ship code 10x faster with parallel AI agents that learn your patterns.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![MCP](https://img.shields.io/badge/MCP-Compatible-8B5CF6?style=flat-square)](https://modelcontextprotocol.io)

---

XRoads is a native macOS application built with SwiftUI that orchestrates multiple AI coding agents -- Claude Code, Gemini CLI, and Codex -- running in parallel on isolated git worktrees. Each agent operates in its own sandboxed environment with real PTY execution, while a central conductor coordinates work distribution, conflict prevention, and intelligent merge resolution.

Unlike browser-based or Electron-wrapped alternatives, XRoads runs as a first-class macOS citizen: Apple Silicon optimized, Keychain-integrated, and built entirely on Swift concurrency primitives. No JavaScript runtime in the main process. No container overhead. Just native performance.

| | |
|---|---|
| **Platform** | macOS 14+ (Sonoma) -- Apple Silicon optimized |
| **Language** | Swift 5.9+ / 66,000+ lines across 209 source files |
| **Architecture** | 52+ Swift actors for compile-time data-race safety |
| **Database** | 21 tables via GRDB.swift versioned migrations |
| **Agents** | Claude Code, Gemini CLI, Codex CLI, custom runtimes |

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Service Architecture](#service-architecture)
- [Database Schema](#database-schema)
- [Comparison with Alternatives](#comparison-with-alternatives)
- [Cross-Platform](#cross-platform)
- [Roadmap](#roadmap)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Testing](#testing)
- [License](#license)
- [Credits](#credits)

---

## Features

### Core Orchestration

- **Parallel Agent Execution** -- Run up to 6 AI agents simultaneously on the same codebase, each in an isolated git worktree with its own branch
- **Conductor Service** -- Central coordinator that distributes PRD stories to agents based on capability, trust scores, and current load
- **Cockpit Lifecycle Manager** -- Full session lifecycle management from initialization through dispatch, execution, merge, and teardown
- **Layered Dispatch** -- Multi-phase dispatch system that breaks PRDs into actionable story assignments with dependency tracking between stories
- **Execution Gate State Machine** -- Approval workflow for high-risk operations with configurable risk thresholds, automatic rollback payloads, and full audit trail
- **Orchestration Recovery** -- Automatic session recovery after crashes, preserving agent state and work-in-progress across restarts
- **Nexus Loops** -- Battle-tested agentic execution patterns with structured prompting, error recovery, session persistence, and clean handoffs

### Agent Support

- **Claude Code** -- Full integration via CLI with PTY-based streaming output and MCP communication
- **Gemini CLI** -- Native adapter with streaming log parsing and context injection
- **Codex CLI** -- Adapter for OpenAI's Codex agent with adapted prompting patterns
- **Custom Runtimes** -- Pluggable runtime system supporting CLI, HTTP, and Docker-based agents via `agent_runtime` configuration
- **MCP Integration** -- Model Context Protocol client/server for bidirectional structured agent communication (TypeScript MCP server included)

### Intelligence (On-Device ML)

All machine learning runs locally on-device. No data leaves the machine. Zero external ML frameworks.

- **MLTrainer Actor** -- Pure Swift implementations of Linear Regression, Naive Bayes, and Decision Tree algorithms for agent performance prediction
- **Learning Engine** -- Records per-story execution metrics (duration, cost, files changed, lines added/removed, test pass rate, conflict count, retries) and builds statistical performance profiles per agent type and task category
- **Agent Memory Repository** -- Persistent memory system where agents store observations, preferences, and learned patterns across sessions with confidence scores and access tracking
- **Trust Score Repository** -- Dynamic trust scores per agent per domain, computed from historical success rates, test outcomes, and conflict frequency. Agents above threshold can auto-merge without human review
- **Conflict Prevention Service** -- Predictive system that analyzes file-level dependencies between concurrent stories and flags potential merge conflicts before agents begin work

### Security (SafeExecutor)

- **SafeExecutor Interceptor** -- Intercepts all agent-requested shell commands, classifies risk level (`low`, `medium`, `high`, `critical`), and routes high-risk operations through the Execution Gate approval workflow
- **Keychain Integration** -- API keys stored in the macOS Keychain via `Security.framework`. Never in plaintext. Never in UserDefaults
- **Sandboxed Worktrees** -- Each agent operates in its own git worktree with restricted filesystem scope
- **Audit Trail** -- Every execution gate decision (approved, denied, auto-approved) is logged with timestamp, approver, and rationale in the `execution_gate` table

### Organization (Org Chart, Budget, Config Versioning)

- **Org Chart Service** -- Define hierarchical agent roles (Chairman, Lead, Worker) with authority levels, goal descriptions, and parent-child relationships
- **Budget Service** -- Per-session and per-agent budget tracking in cents, with configurable warning thresholds (default 80%), hard stops, throttling, daily limits, and per-story limits
- **Config Versioning** -- Every configuration change is snapshotted via `config_snapshot` with version number, diff, change reason, and changed-by attribution
- **Workspace Management** -- Multi-project workspace support with per-workspace slot limits, budget allocation, and color-coded organization

### Monitoring (Heartbeat, Scheduling)

- **Heartbeat Service** -- Configurable health checks per agent slot (default 30s interval) with consecutive failure tracking (max 5) and automatic recovery triggers
- **Agent Status Monitor** -- Real-time status aggregation across all active agent slots with event bus publication
- **Cost Event Tracking** -- Per-request token usage and cost tracking by provider, model, input/output tokens, and cost in cents
- **Scheduled Runs** -- Cron-based or trigger-based automated orchestration runs with result tracking and next-run computation
- **Chairman Feed** -- Aggregated orchestration event stream for high-level session monitoring

### Native macOS UI

- **Cockpit Dashboard** -- Real-time 6-slot terminal grid with streaming PTY output per agent
- **Seven-Tab Settings** -- General, CLI Paths, MCP, API Keys, Budget, Runtimes, Advanced
- **Command Palette** -- Keyboard-driven command palette (Cmd+K) for rapid navigation and actions
- **Conflict Resolution Sheet** -- Side-by-side diff viewer for resolving merge conflicts between agent outputs
- **Orchestration History** -- Browsable history of past orchestration sessions with metrics and outcomes
- **PRD Loader** -- Load and parse PRD files with automatic story extraction and dependency graphing
- **Art Direction Views** -- Design system and art bible integration for UI-focused orchestration
- **Dark Pro Theme** -- Designed for extended coding sessions with consistent dark color system

---

## Quick Start

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Swift 5.9+ (included with Xcode 15+)
- At least one AI CLI tool installed: `claude`, `gemini`, or `codex`
- Node.js 18+ (for the MCP server)

### Build and Run

```bash
# Clone
git clone https://github.com/neurogrid/xroads.git
cd xroads

# Build with Swift Package Manager
swift build

# Run
swift run XRoads
```

Or with Xcode:

```bash
# Build via xcodebuild
xcodebuild -scheme XRoads -destination 'platform=macOS' build

# Or open in Xcode directly
open Package.swift
# Then: Product > Run (Cmd+R)
```

### MCP Server Setup

```bash
cd xroads-mcp
npm install
npm run build
npm start
```

### First Session

1. Launch XRoads
2. Open **Settings** (Cmd+,) and configure CLI paths under the **CLI Paths** tab
3. Add API keys under the **API Keys** tab (stored in Keychain)
4. Open a git repository as your workspace
5. Load a PRD or describe your task in the chat panel
6. Assign agents to slots, configure budgets, and start the orchestration

---

## Architecture

```
XRoads/
  App/                    @main entry point, AppDelegate
  Models/                 48 Codable/GRDB data models
  Views/
    Cockpit/              Main dashboard and agent slot views
    Dashboard/            Orchestrator visualization
    Settings/             Seven-tab settings interface (7 sub-views)
    Components/           Reusable UI components
    Orchestrator/         Orchestration control and status views
    PRD/                  PRD loading, editing, and preview
    ArtDirection/         Design system and art bible views
    Skills/               Skill management interface
  ViewModels/             @Observable view models
  Services/               52+ actor-based services
  Resources/
    Skills/               Built-in skill definition files
```

### State Management

`AppState` is the root `@Observable` object on `@MainActor`, decomposed into focused sub-states to avoid a god-object antipattern:

| Sub-State | Responsibility |
|---|---|
| `DashboardState` | Terminal slots, orchestrator visualization, git info |
| `DispatchState` | Phase tracking, progress, messages, dispatch layers |
| `OrchestrationSubState` | Active agents, health status, merge state, session history |

All services are initialized through `ServiceContainer` and injected via SwiftUI's environment system using `@Environment(\.appState)`.

### Concurrency Model

Every service with mutable state is a Swift `actor`, providing compile-time data-race safety. Cross-actor communication uses `async/await` throughout -- no locks, no dispatch queues, no callback pyramids. UI-bound code is annotated with `@MainActor` for safe SwiftUI updates.

### Process Execution

Agents run in real pseudo-terminals via macOS `/usr/bin/script`, not piped subprocesses. This ensures accurate terminal emulation including ANSI escape codes, interactive prompts, and proper signal handling. The `PTYProcess` actor manages the full lifecycle of each terminal session.

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI (macOS 14+ / Sonoma) |
| Database | GRDB.swift 7 (SQLite with type-safe queries) |
| Concurrency | Swift Actors + structured async/await |
| Process Execution | Real PTY via `/usr/bin/script` |
| Secrets Storage | macOS Keychain (Security.framework) |
| Agent Communication | MCP (Model Context Protocol) |
| MCP Server | TypeScript / Node.js 18+ |
| Machine Learning | Pure Swift math (zero external frameworks) |
| Package Manager | Swift Package Manager |
| Minimum Target | macOS 14.0 (Sonoma), Apple Silicon + Intel |

---

## Service Architecture

### Orchestration Layer

| Actor | Role |
|---|---|
| `ConductorService` | Central coordinator -- distributes stories to agents based on capability, trust, and load |
| `CockpitLifecycleManager` | Full session lifecycle: init, dispatch, execute, merge, teardown |
| `LayeredDispatcher` | Multi-phase PRD-to-story dispatch with dependency analysis |
| `OrchestratorService` | High-level orchestration commands and state transitions |
| `ClaudeOrchestrator` | Claude-specific orchestration logic and prompt construction |
| `UnifiedDispatcher` | Single entry point routing all dispatch operations |
| `ChatDispatchParser` | Parses natural language chat input into orchestration actions |
| `OrchestrationRecoveryService` | Restores session state after crash or unexpected termination |
| `OrchestrationHistoryService` | Records and queries past orchestration sessions |

### Agent Execution

| Actor | Role |
|---|---|
| `AgentLauncher` | Spawns agent CLI processes in isolated worktrees with context injection |
| `PTYProcess` | Real pseudo-terminal execution via macOS `script` command |
| `ProcessRunner` | Low-level process management with streaming stdout/stderr capture |
| `LoopLauncher` | Manages Nexus Loop execution with retry and structured handoffs |
| `LoopScriptLocator` | Discovers loop script files on disk for each agent type |
| `ActionRunner` | Executes discrete actions requested by agents via the action registry |
| `ActionRegistry` | Maps action types to their executor implementations |
| `ToolExecutor` | Runs MCP tool calls from connected agents |

### Intelligence and Learning

| Actor | Role |
|---|---|
| `LearningEngine` | Records execution metrics and computes per-agent performance insights |
| `MLTrainer` | On-device ML: Linear Regression, Naive Bayes, Decision Tree (pure Swift) |
| `ConflictPreventionService` | Predicts file-level merge conflicts between concurrent agent tasks |
| `AgentMemoryRepository` | Persistent cross-session agent memory with confidence scoring |
| `TrustScoreRepository` | Dynamic per-agent per-domain trust scores with auto-merge thresholds |
| `LearningRepository` | Storage layer for learning records and performance profiles |
| `DependencyTracker` | Tracks inter-story dependencies to prevent execution ordering violations |

### Safety and Governance

| Actor | Role |
|---|---|
| `SafeExecutorInterceptor` | Classifies risk level of agent shell commands and gates execution |
| `ExecutionGateStateMachine` | State machine for approval workflow (pending/approved/denied) |
| `ExecutionGateRepository` | Persistence and query for gate decisions and audit logs |
| `BudgetService` | Enforces per-session and per-agent spending limits with alerts |
| `BudgetRepository` | Storage for budget configs, alerts, and spending history |
| `CostEventRepository` | Token usage and cost tracking per provider/model/request |

### Git and Workspace

| Actor | Role |
|---|---|
| `GitService` | Worktree creation, branch management, status queries |
| `GitMaster` | High-level git intelligence: merge strategy, conflict analysis, resolution |
| `MergeCoordinator` | Coordinates merging completed agent worktrees back to the main branch |
| `WorkspaceRepository` | Multi-project workspace persistence and switching |
| `ProjectContextReader` | Scans repo structure, dependencies, and conventions for agent context |
| `RepoDetector` | Auto-detects project type, framework, language, and toolchain |

### Organization and Configuration

| Actor | Role |
|---|---|
| `OrgChartService` | Hierarchical agent role management (Chairman/Lead/Worker) |
| `OrgRoleRepository` | Persistence for org chart role definitions |
| `ConfigSnapshotRepository` | Versioned configuration snapshots with diffs and attribution |
| `ConfigChecker` | Validates CLI tool availability and system requirements at startup |
| `SkillRegistry` | In-memory registry of loaded skill definitions |
| `SkillLoader` | Discovers and loads skill markdown files from `Resources/Skills/` |
| `SessionPersistenceService` | Saves and restores full session state to SQLite |
| `CockpitSessionRepository` | CRUD operations for cockpit session records |

### Monitoring and Communication

| Actor | Role |
|---|---|
| `HeartbeatService` | Periodic health checks per agent slot with failure escalation |
| `HeartbeatRepository` | Persistence for heartbeat configuration and pulse history |
| `AgentStatusMonitor` | Real-time aggregation of all agent slot statuses |
| `AgentEventBus` | Pub/sub event bus for decoupled inter-service communication |
| `MessageBusService` | Agent-to-agent message routing with broadcast support |
| `SlotMessagePublisher` | Publishes slot state changes for UI layer consumption |
| `MCPClient` | Model Context Protocol client for structured agent communication |
| `ChairmanFeedService` | Aggregates orchestration events into a chairman-level activity feed |
| `StatusMonitor` | System-wide status monitoring and health aggregation |
| `CockpitCouncilClient` | Client for council-level decision queries |

---

## Database Schema

XRoads uses GRDB.swift with 15 versioned migrations creating 21 tables. All migrations run automatically on first launch and on version upgrades. The database is stored at `~/Library/Application Support/XRoads/cockpit.sqlite`.

| Migration | Tables | Purpose |
|---|---|---|
| `v1` | `cockpit_session`, `agent_slot` | Core session and agent slot tracking |
| `v2` | `metier_skill` | Skill definitions with family grouping |
| `v3` | `agent_message` | Inter-agent message passing |
| `v4` | -- (alter) | Add `currentTask` to `agent_slot` |
| `v5` | `execution_gate` | Risk-based command approval workflow |
| `v6` | `cost_event` | Per-request token and cost tracking |
| `v7` | `org_role` | Hierarchical agent role definitions |
| `v8` | `budget_config`, `budget_alert` | Budget limits and alert thresholds |
| `v9` | `heartbeat_config` | Per-slot health check configuration |
| `v10` | `scheduled_run` | Cron/trigger-based automated runs |
| `v11` | `workspace`, `agent_runtime` | Multi-workspace and custom runtime support |
| `v12` | `config_snapshot` | Versioned configuration with diffs |
| `v13` | `learning_record`, `performance_profile` | ML training data and computed profiles |
| `v14` | `agent_memory` | Persistent cross-session agent memory |
| `v15` | `trust_score` | Per-agent per-domain trust computation |

Foreign keys are enforced globally. Cascade deletes ensure referential integrity when sessions or slots are removed. In-memory database constructor is available for testing.

---

## Comparison with Alternatives

| Capability | XRoads | Cursor | Windsurf | Devin | Claude Code (solo) |
|---|---|---|---|---|---|
| Parallel agents | Up to 6 | 1 | 1 | 1 | 1 |
| Agent types | Claude, Gemini, Codex, custom | Proprietary | Proprietary | Proprietary | Claude only |
| Git worktree isolation | Native per-agent | None | None | Container | None |
| On-device ML | LinearReg, NaiveBayes, DecisionTree | None | None | None | None |
| Trust scoring | Per-agent per-domain with auto-merge | None | None | None | None |
| Execution gating | Risk-classified approval workflow | None | None | None | None |
| Budget controls | Session, agent, daily, per-story | None | Basic | None | None |
| Conflict prevention | Predictive, pre-execution | None | None | None | None |
| Agent memory | Persistent cross-session | Context window | Context window | Context window | CLAUDE.md only |
| Org hierarchy | Chairman / Lead / Worker roles | None | None | None | None |
| Config versioning | Full snapshot with diffs | None | None | None | None |
| Self-hosted | Fully local, no cloud dependency | Cloud-dependent | Cloud-dependent | Cloud-dependent | Local (single agent) |
| Open source | Yes | No | No | No | No |
| Runtime | Native macOS (SwiftUI) | Electron | Electron | Web browser | Terminal |

---

## Cross-Platform

A cross-platform port of XRoads exists for Windows and Linux:

**XRoads Tauri** -- Built with Tauri 2, React 19, TypeScript, and a Rust backend. The Tauri version implements the same orchestration architecture with a Rust service layer mirroring the Swift actor design. Both versions share the same conceptual model, database schema design, and PRD-driven workflow.

Repository: `CrossRoads-Tauri/`

---

## Roadmap

- [x] Multi-agent parallel execution (6 slots)
- [x] Git worktree isolation per agent
- [x] GitMaster intelligent conflict resolution
- [x] PRD-driven dispatch with dependency tracking
- [x] Nexus Loop integration (Claude, Gemini, Codex)
- [x] MCP client/server integration
- [x] On-device ML (LinearReg, NaiveBayes, DecisionTree)
- [x] Persistent agent memory and trust scoring
- [x] Budget controls with alerts and hard stops
- [x] Execution gating with risk classification
- [x] Org chart with role hierarchy
- [x] Config versioning with snapshots
- [x] Heartbeat monitoring and auto-recovery
- [ ] Plugin system for third-party agent runtimes
- [ ] Team collaboration with shared sessions and RBAC
- [ ] Optional encrypted cloud sync for learning data and agent memory
- [ ] iOS companion app for remote monitoring and gate approvals
- [ ] Advanced ML: gradient boosting for cost prediction, RL for agent assignment
- [ ] Integrated test runner (XCTest/pytest/Jest) for real-time feedback during execution
- [ ] Visual PRD builder with drag-and-drop story dependency graphs

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+N | New Worktree |
| Cmd+W | Close Worktree |
| Cmd+. | Stop Agent |
| Cmd+K | Command Palette |
| Cmd+L | Clear Logs |
| Cmd+, | Settings |

---

## Testing

```bash
# Run the full test suite
swift test

# Run with verbose output
swift test --verbose

# Run a specific test
swift test --filter XRoadsTests.SomeTestClass
```

The test target (`XRoadsTests`) depends on `XRoadsLib` and GRDB. All database-dependent tests use the in-memory `CockpitDatabaseManager()` initializer to avoid touching the production database.

---

## License

TBD

---

## Credits

Built by [Neurogrid](https://neurogrid.me).

XRoads is the product of an engineering philosophy: AI agents are most effective when they operate in parallel, within clear boundaries, under intelligent supervision. The orchestrator should be as fast and reliable as the agents it commands.

### Acknowledgments

- **[Maestro](https://github.com/its-maestro-baby/maestro)** -- Pioneering multi-terminal AI orchestration. XRoads takes inspiration from Maestro's parallel execution model while adding loop integration and intelligent merge resolution for the macOS ecosystem.
- **[Ralph Wiggum Loop](https://www.reddit.com/r/ClaudeAI/comments/1jazz5r/introducing_the_ralph_wiggum_loop_a_system_for/)** -- The methodology behind robust agentic loops. Nexus Loops adapts these patterns for multi-agent coordination.
- **[Model Context Protocol](https://modelcontextprotocol.io/)** -- Anthropic's open standard for structured AI-tool communication.
- **[GRDB.swift](https://github.com/groue/GRDB.swift)** -- The SQLite toolkit that makes type-safe database access in Swift a pleasure.
