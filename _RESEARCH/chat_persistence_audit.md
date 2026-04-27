# Chat Persistence & Config — Audit

Phase 1 deliverable for the *Repository-aware Chat History & Persistence/Config* mission.

- Date: 2026-04-27
- Scope: `XRoads/Services/{ChatHistoryRepository, SessionPersistenceService, NotesSyncService, WorkspaceRepository, ConfigSnapshotRepository, ConfigChecker}.swift`
- Read-only neighbours: `RepoDetector`, `ProjectContextReader`, `ChatDispatchParser`, `CockpitDatabaseManager`, `ServiceContainer`
- Code root reality: the Swift package lives at `_CODE/`, not `_CODE/XRoads/` as the mission brief states. SPM `XRoadsLib` target points at `_CODE/XRoads/` (sources). I work from `_CODE/`.

---

## 1. Service inventory

### 1.1 `ChatHistoryRepository.swift` (211 LOC) — actor

| Aspect | Value |
|---|---|
| Public API | `saveMessage(_:)`, `saveMessages(_:)`, `fetchHistory(sessionId:limit:)`, `fetchRecent(limit:)`, `buildChatSummary(sessionId:maxMessages:)`, `saveWakePrompt(_:)`, `fetchLatestWakePrompt(sessionId:)`, `buildWakeContext(sessionId:)`, `saveHarnessIteration(_:)`, `fetchPendingProposals(limit:)`, `markApplied(id:impact:)`, `fetchProposalsForTarget(_:limit:)`, `buildHarnessSummary()` |
| Storage | GRDB SQLite — three tables: `chat_history` (v17), `cockpit_wake_prompt` (v17), `harness_iteration` (v18) |
| Threading | `actor`, all queries via injected `DatabaseQueue` (GRDB's own serial dispatch). Convenience init from `CockpitDatabaseManager`. |
| Instantiated | `AppState.bootstrapCockpit()` line 126 — **only when cockpit panel opens**. Not in `ServiceContainer` protocol. |
| Callers | `CockpitViewModel` (held as `chatHistoryRepo`), `OrchestratorChatView.swift` (read via `appState.cockpitViewModel?.chatHistoryRepo`), `AppState.swift` (event listeners persist slot launch / termination as system messages). |
| Test coverage | **None.** No file under `XRoadsTests/` or `Tests/` references it. |
| Issues | Dependency on cockpit being booted. Idle-state chat panel cannot persist a message until the user opens the cockpit, even though the repo is conceptually independent of cockpit lifecycle. |

### 1.2 `SessionPersistenceService.swift` (149 LOC) — actor

| Aspect | Value |
|---|---|
| Public API | `saveSession(_:)`, `loadSessions(for:)`, `lastSession(for:)`, `updateHandoff(sessionId:repoPath:payload:)`, `updateConversationId(sessionId:repoPath:agent:conversationId:)` |
| Storage | **File-based.** `<repoPath>/.crossroads/sessions.json`. Adds `.crossroads/` to repo's `.gitignore` on first write. |
| Threading | `actor`, synchronous file I/O wrapped in `async`. JSON encoder is `.iso8601` + sorted keys. |
| Instantiated | `DefaultServiceContainer.init()` (default arg). |
| Callers | `LoopLauncher`, `WorktreeFactory`, `AppState` (5 sites: save on session start, on agent assignment, on PRD load, plus handoff + conversation-id updates), `OrchestrationRecoveryService`. |
| Test coverage | **None.** |
| Issues | Different concept of "session" from the DB-backed `cockpit_session` table. Two persistence systems for two notions of "session" with overlapping naming — clear context decay risk. The model `Session` (orchestration session, file-based) is distinct from `CockpitSession` (cockpit lifecycle, DB). Both carry `id`, `createdAt`, `updatedAt`, `status`. |

### 1.3 `NotesSyncService.swift` (94 LOC) — `struct: @unchecked Sendable`

| Aspect | Value |
|---|---|
| Public API | `syncNotesToWorktree(repoPath:assignment:)`, `syncNotesBack(repoPath:assignment:)` |
| Storage | **File-based.** Repo: `<repoPath>/notes/<sanitized-branch>/{decisions,learnings,blockers}.md`. Mirror in worktree: `<worktreePath>/notes/{decisions,learnings,blockers}.md`. |
| Threading | Pure value type, `FileManager.default`, an `ISO8601DateFormatter` held as a `let` (@unchecked Sendable rationale documented inline). |
| Instantiated | `DefaultServiceContainer.init()`. |
| Callers | `LoopLauncher`, `ServiceContainer`. |
| Test coverage | **None.** |
| Issues | `@unchecked Sendable` is justified by the comment but `ISO8601DateFormatter` is documented Sendable-by-construction since macOS 13 — the unchecked could be tightened. Append-on-syncBack is non-atomic (`FileHandle.seekToEnd` + `write`); concurrent writers can interleave entries. |

### 1.4 `WorkspaceRepository.swift` (109 LOC) — actor

| Aspect | Value |
|---|---|
| Public API | `createWorkspace(_:)`, `fetchAll()`, `fetchActive()`, `switchActive(id:)`, `updateWorkspace(_:)`, `deleteWorkspace(id:)` |
| Storage | GRDB SQLite — `workspace` table (v11). |
| Threading | `actor`, GRDB `DatabaseQueue`. |
| Instantiated | `WorkspaceSwitcherView.init` accepts an optional one (line 22), nothing wires it; `AppState.bootstrapCockpit` does **not** create one. |
| Callers | `WorkspaceSwitcherView` only — and that view receives `nil` by default. Effectively dead-code today. |
| Test coverage | **None.** |
| Issues | No `fetchByProjectPath(_:)` — required to bind a chat to a workspace from a repo path detected by `RepoDetector`. No call site upserts on first repo open, so the table stays empty in practice. |

### 1.5 `ConfigSnapshotRepository.swift` (78 LOC) — actor

| Aspect | Value |
|---|---|
| Public API | `createSnapshot(_:)`, `fetchSnapshots(sessionId:configType:)`, `fetchByVersion(sessionId:configType:version:)`, `getLatest(sessionId:configType:)` |
| Storage | GRDB SQLite — `config_snapshot` table (v12). Auto-versioned (MAX(version)+1) per `(sessionId, configType)`. |
| Threading | `actor`, `DatabaseQueue`. |
| Instantiated | `ConfigHistoryView.init` accepts optional, `IntelligenceSheetView` references symbol — nothing in `AppState` or `ServiceContainer` instantiates it. |
| Callers | `CockpitViewModel.configSnapshotRepo` (private optional, line 121, never assigned in current bootstrap path). |
| Test coverage | **None.** |
| Issues | No diff function (signature has a `diff` column on the model but no service method computes one). No `restore` semantics — only `getLatest`. |

### 1.6 `ConfigChecker.swift` (286 LOC) — actor

| Aspect | Value |
|---|---|
| Public API | `checkGit()`, `checkClaude()`, `checkGemini()`, `checkCodex()`, `checkAll(forceRefresh:)`, `isAgentAvailable(_:)`, `clearCache()` |
| Storage | In-memory cache (5 min). |
| Threading | `actor`. Spawns `Process` for `which`, with `PathResolver.enhancedPATH`. |
| Instantiated | `ConfigChecker()` directly inside `WorktreeCreateSheet` line 59 and `StartSessionSheet` line 71 — two separate instances, two separate caches. |
| Callers | The two views above. |
| Test coverage | **None.** |
| Issues | Two parallel instances → cache misses across views. No DI. `getVersion(...)` is implemented but never returned in `checkTool` (versions are always nil in the produced `ConfigCheckResult`). |

---

## 2. Data model map

### 2.1 `ChatHistoryEntry` → table `chat_history` (v17)

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` (text PK) | Default `UUID()` |
| `sessionId` | `UUID?` (text, FK → `cockpit_session(id)` ON DELETE CASCADE) | **Cascade is destructive: deleting a cockpit session wipes its chat history.** |
| `role` | `String` | `"user" | "assistant" | "system"` — no enum, free-form string |
| `content` | `String` | |
| `mode` | `String?` | `"api" | "terminal" | "artDirector" | "event" | "brain"` — also free-form |
| `metadata` | `String?` | JSON blob |
| `createdAt` | `Date` | |

Indexes: `idx_chat_history_session`, `idx_chat_history_created`. No index on (sessionId, createdAt) for typical "fetch history for session, ordered" — small N, fine for now.

### 2.2 `CockpitWakePrompt` → `cockpit_wake_prompt` (v17)

`id, sessionId?, prompt, observations?, pendingActions?, slotSummaries?, createdAt`. FK cascades from `cockpit_session`.

### 2.3 `HarnessIteration` → `harness_iteration` (v18)

`id, sessionId?, target, critique, proposal, applied(bool), impact?, createdAt`.

### 2.4 `Workspace` → `workspace` (v11)

`id, name, projectPath, color, icon?, isActive, maxSlots, totalBudgetCents?, metadata?, lastAccessedAt, createdAt`. Indexed on `projectPath` (non-unique). **Two workspaces can collide on the same `projectPath` — there is no uniqueness constraint.**

### 2.5 `ConfigSnapshot` → `config_snapshot` (v12)

`id, sessionId?, workspaceId?, configType, version, data, diff?, changedBy, changeReason?, createdAt`. FKs to `cockpit_session`, `workspace`, both `ON DELETE SET NULL`.

### 2.6 `Session` (file-based, separate)

`id, name, worktrees[UUID], status, createdAt, repoPath?, conversationIds, handoffPayload?, parentSessionId?, updatedAt`. Persisted as `<repoPath>/.crossroads/sessions.json`.

### 2.7 Identifier strategy

UUIDv4 everywhere, stored as text. Stable, no collision risk in practice.

### 2.8 Migration story

GRDB `DatabaseMigrator` with named migrations `v1`–`v19`. Migrations are append-only; once applied they cannot be undone in place. Strategy is sound for forward evolution. No down-migration support — destructive schema rewrites would require a rebuild script + data export.

### 2.9 Row counts (local install, 2026-04-27)

DB path: `~/Library/Application Support/XRoads/cockpit.sqlite`. **DB file does not exist on this machine** — the cockpit has never been bootstrapped here. So real-world counts are unknown; testing must seed.

---

## 3. Repo-awareness gap analysis

### 3.1 How is the "current repository" detected at chat start?

Today: not as such. The chat sees `appState.projectPath: String?` (a single global path, set by user folder picker or `RepoDetector` when the app launches with a cwd). `OrchestratorChatView` reads this directly.

`RepoDetector` (UserDefaults-backed, `xroads.recentRepos`, max 10) maintains a separate list — duplicated state with `Workspace` (DB).

### 3.2 Where is the repo identifier stored alongside a chat session?

Indirectly:

- `ChatHistoryEntry.sessionId` → `cockpit_session.id` → `cockpit_session.projectPath`. So a chat IS bound to a repo *if* a cockpit session exists.
- If no cockpit session: chat persists with `sessionId = nil` (the column allows null), and the repo binding is lost.
- `Workspace` table has `projectPath` but is never joined to anything chat-related.

### 3.3 What repo-scoped context gets auto-injected today?

`ProjectContextReader.readContext(projectPath:activePRDURL:)` returns a `ChairmanInput` with:

- last 20 commits via `GitService.getRecentCommits`
- open branches via `git branch --format`
- all PRD summaries via `PRDScanner` (recursive find of `prd.json`) + the active dispatch PRD if missing
- last cockpit session via `CockpitSessionRepository.fetchAllSessions().filter { $0.projectPath == projectPath }.first`

Crucially this is consumed by Chairman for cockpit deliberation, **not** injected into the orchestrator chat as a system preamble. The chat itself only sees `appState.projectPath` and the current branch (via `viewModel.currentBranch`). CLAUDE.md, AGENTS.md, runbooks under `_OPS/` are **not** read by any service today.

### 3.4 What's missing for a chat to be fully repo-aware?

1. A unified "load context for chat session" facade. Today: scattered between `OrchestratorChatViewModel.loadContext`, `ProjectContextReader`, and `RepoDetector`.
2. Reading CLAUDE.md / AGENTS.md / README.md / runbooks (_OPS/) — no service does this.
3. Persisting a `repoContextHash` on the chat session so resume can detect drift.
4. Linking chat history rows to a stable repo identifier (path is fragile if the user moves the folder).
5. UI surfacing of the loaded context as collapsible chips.

---

## 4. UI surface scan

### 4.1 Existing chat / history surfaces

| View | Path | Role |
|---|---|---|
| `OrchestratorChatView` | `Views/Orchestrator/OrchestratorChatView.swift` (1060 LOC) | Active chat panel (left). Hosts `ChatMessageView`, `ChatInputBar`, `ChatContextBar`. |
| `OrchestratorSidebar` | (referenced in `MainWindowView` line 184) | Idle-state placeholder for the left panel. The active `OrchestratorChatView` is the next-step target. |
| `OrchestrationHistorySheet` | `Views/OrchestrationHistorySheet.swift` | Past *orchestration runs*, not chat sessions. Distinct concept. |
| `ConfigHistoryView` | `Views/Settings/ConfigHistoryView.swift` | Versioned config snapshots (admin/audit). |
| `WorkspaceSwitcherView` | `Views/WorkspaceSwitcherView.swift` (224 LOC) | Workspace picker UI; takes optional `WorkspaceRepository` (always nil). |
| `CockpitChatPanelTests` exists but no `OrchestratorChatViewTests` | `XRoadsTests/CockpitChatPanelTests.swift` | Tests for cockpit-specific chat panel. |

### 4.2 Navigation host candidates for the new history panel

**Current main layout** (`MainWindowView.agenticModeLayout`):

```
TitleBar
[Recovery banner]
HStack(
  CollapsiblePanel(left, 320px) → OrchestratorSidebar (idle) | OrchestratorChatView (active),
  Center → StatusBar + HeroIdleState,
  CockpitModeView (300px, optional),
  RightSidePanel (280px, inspector)
)
BottomBar
```

The left panel is a `CollapsiblePanel` already wired with `@AppStorage("chatPanelExpanded")` and width persistence. It currently has two states (idle / active chat). A "history" mode is the third natural state.

**Two design candidates** (the brief mandates I ask before choosing):

- **Candidate A — embedded in left panel.** Replace `OrchestratorSidebar` with a `ChatHistoryListView`. The active chat view stays. Toggle chevron at top: list ⇄ active chat. Pinning, archive, delete inline. Matches Cursor / Claude Code idiom. No new sheet.
- **Candidate B — sheet from TitleBar.** New `chatHistory` button in `TitleBar`. Opens a full-window sheet (similar to `OrchestrationHistorySheet`) listing all chats. Click row → restore into left panel. Matches Antigravity / VSCode "Show All Chats" idiom.

Candidate A is the better fit given the existing architecture (panel already toggles, list/active is symmetric). Candidate B requires a new sheet entry point and duplicates the panel's purpose.

### 4.3 Screenshot of current state

Cannot capture without launching the app. Will produce one at Phase 4 if confirmed feasible (the build must boot first; per HANDOFF.md and EMERGENCY_CLEANUP.md the codebase is in active flux). If launch is not feasible during this mission, I will state so explicitly per `_CROSSROADS_SWIFT/CLAUDE.md` honesty clause.

---

## 5. Risks, bugs and open questions

### 5.1 Real bugs found during audit (Tier-A)

1. **`AppState.swift:215–227` — control flow bug.** `wakeBrain(reason:)` is nested inside the `if let repo = ..., let sessionId = ...` block, so the brain only wakes when a cockpit session exists *and* the chat history repo is reachable. The brain wake-up should be unconditional on slot termination. The indentation suggests the author wanted it outside the `if`. Outside the audit's owned services, but I'll flag it in the PR per `CLAUDE.md` §10 senior dev override.
2. **`ConfigChecker.checkTool(name:)` — version always nil.** `checkTool` calls `getVersion(path:)` and **discards it**: `return .available(tool: name, path: path, version: version)` — wait, it does pass `version`. Re-reading line 283-285: `let version = await getVersion(path: path); return .available(tool: name, path: path, version: version)`. Version IS captured. False alarm. Strike.
3. **Two parallel `ConfigChecker` instances** (`WorktreeCreateSheet` line 59, `StartSessionSheet` line 71). Each holds its own 5-min cache. Acceptable for now; flag for future DI cleanup.
4. **`AppState.bootstrapCockpit` reachability.** `ChatHistoryRepository` is created only if the cockpit panel is opened. The orchestrator chat panel can be opened without the cockpit, in which case writes silently fail (the persistence calls in `OrchestratorChatView` are guarded by `if let repo = viewModel.chatHistoryRepo`). User-visible effect: if a user types a chat message before opening the cockpit, the message is lost on app restart.
5. **Two notions of "session"** (`Session` file-based vs `CockpitSession` DB). The mission's `WorkspaceRepository` test expectations ("bind session ↔ workspace ↔ repo path; rename/move repo") implicitly require us to choose one. I'll assume the DB cockpit session is the source of truth for repo-aware chat, and document the file-based one as orchestration-runtime metadata only.
6. **`workspace.projectPath` is not unique.** Two `Workspace` rows can share a path; `fetchByProjectPath` would return ambiguous results. Add a unique index (or document tie-break) before binding chats to workspaces.
7. **Free-form string columns** (`role`, `mode` on `chat_history`). Should be enums in code with a `rawValue` round-trip, validated on insert. Out of scope to refactor; flag.

### 5.2 Decisions the human must make before Phase 3

These are the **hard-stop questions** per the mission brief §3:

- **Q1 — Storage backend:** clear (GRDB SQLite for chat history + config snapshots + workspaces; JSON files for orchestration sessions and notes). **No question needed.**
- **Q2 — Threading model:** clear (actors + GRDB DatabaseQueue, MainActor for ViewModels). **No question needed.**
- **Q3 — Navigation host for the panel:** **Question:** Candidate A (history list embedded in the left collapsible panel, toggle list ⇄ active chat) or Candidate B (sheet from TitleBar)? My recommendation is **A** for fit and minimal disruption. Awaiting confirmation.
- **Q4 — Destructive schema migration:** **Not strictly required.** What we need can be added with a non-destructive `v20` migration:
  - Add columns to `chat_history`: `title TEXT?`, `pinned BOOLEAN DEFAULT 0`, `archivedAt DATETIME?` — OR introduce a sibling `chat_session(id, sessionId?, repoPath, branch, title, pinned, archivedAt, lastActivityAt, repoContextHash, ...)` table.
  - Add unique index on `workspace(projectPath)` — but this **is destructive if duplicates exist in any installed DB**. Since the table is empty in practice, the risk is low, but it's the only operation that could fail on existing data.

  **Question:** acceptable to add `UNIQUE INDEX idx_workspace_project_path` in `v20`, with an upfront migration that deletes duplicate rows (keeping the most recently `lastAccessedAt`) before adding the constraint? Or prefer to add a *non-unique* index and de-duplicate at read time?

- **Q5 — Title source-of-truth:** chat session title can be (a) derived from first user message, (b) stored on `cockpit_session` (already has `chairmanBrief` text), or (c) stored on a new `chat_session` table. My preference is (c) — separates concerns from cockpit lifecycle. Awaiting confirmation.

- **Q6 — Resume semantics for missing repo path:** when a saved chat references a `repoPath` that no longer exists, should the row stay (banner: "Repo moved? Pick new path…") or be auto-archived? Brief says "show banner: never silent break." Confirming this is the chosen behavior — banner only, never auto-archive.

### 5.3 Out-of-scope items I want to surface

- The bug at `AppState.swift:215–227` (wakeBrain in wrong scope) — I'll fix in the PR per senior dev override.
- The two parallel `ConfigChecker` instances — flag in PR but do not refactor.
- The `_unchecked Sendable` on `NotesSyncService` could be tightened (`ISO8601DateFormatter` is `Sendable` since macOS 13). Flag, do not fix.

---

## 6. Plan readiness

If Q3, Q4, Q5, Q6 are answered, Phase 2 (tests) and Phase 3 (UI + pipeline) can proceed. My intended Phase 3 architecture:

```
ChatSessionLoader (new facade)
  ├─ resolveRepoPath() → WorkspaceRepository.fetchByProjectPath ?? RepoDetector.detect
  ├─ readProjectContext() → ProjectContextReader.readContext + read CLAUDE.md / AGENTS.md / runbooks
  ├─ snapshotConfig() → ConfigSnapshotRepository.createSnapshot + ConfigChecker.checkAll
  ├─ buildPreamble() → structured ContextPreamble (chips: repo, branch, last 10 commits, PRDs found, runbooks loaded)
  └─ persistBinding() → ChatHistoryRepository.saveMessage(system preamble) + chat_session row

ChatHistoryListView (new)
  ├─ viewModel: ChatHistoryViewModel (depends on ChatHistoryPresenting protocol)
  ├─ filters: All | This Repository | Search
  ├─ row actions: Pin, Archive, Delete, Resume
  └─ embedded inside the left CollapsiblePanel (Candidate A)

WorkspaceRepository (extension)
  └─ fetchByProjectPath(_:) → Workspace?
  └─ ensureWorkspace(forRepoPath:) → upsert
```

Tests planned per `CLAUDE.md` mandate:

- temp-file SQLite per test (no mocks),
- one assertion per test where possible,
- happy path + repo-moved + repo-renamed + multi-repo + concurrent-write per service.

---

## 7. End state of Phase 1

- File: `_RESEARCH/chat_persistence_audit.md` (this file).
- Status: **awaiting confirmation on Q3, Q4, Q5, Q6** before Phase 2 begins.
- No code changes made.
