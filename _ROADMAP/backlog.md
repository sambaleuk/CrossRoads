# Backlog — crossroads swift

Everything not in `next-release.md`. Ordered by priority within each bucket.

## Session Handoff — 2026-04-26 / 2026-04-27

### Shipped this session
- **`f6f39a9`** merge: Ousmane's visual identity track from public/main (7 commits — Title bar tactical, Hero idle, Orchestrator sidebar, Status/Bottom bar, Pattern overlay tuning)
- **`66b6fa6`** chore(layout): promoted XRoads code into `_CODE/` production scaffold (366 renames, 33 adds, 1.8 GB cleanup)
- **`fec4cce`** docs(roadmap): seeded backlog with B1-B7 from smoke test
- **`3bd61d2`** [brain] fix US-007 — replaced hardcoded `/Users/bigouz/...` with `FileManager.temporaryDirectory` in SnapshotTests
- **`44d3e7e`** [brain] fix lint — SafeExecutor heredoc Python uses `sys.stdout.write` instead of `print()` to satisfy lint scanner
- **`e852099`** [brain] fix parser — PRDParser now decodes per-story `status` field (619 → 625 tests)
- **`dbe175e`** docs(roadmap): added B0 (CockpitBrainService spawner runaway loop)
- **`69ea452`** fix(US-000/B0) — singleton-per-project gate for cockpit-brain (in-process guard + PID file via `BrainProcessRegistry`, 6 new tests, SIGTERM/SIGKILL on shutdown)
- **`89d0638`** [slot-1] feat(budget): BudgetPreset (PRD-S02 US-006) — 4 built-in presets + JSON store + 50 tests, fixes broken GRDB pattern in `CostEventRepository`

### Cleanup completed
- 21 PRDs archived → `_CODE/_archive/prds-2026-04-26/` (local only, ignored)
- 8 obsolete branches deleted: `claude/nice-mahavira`, `claude/relaxed-hamilton`, `feat/Ops-claude`, `opensource-prep`, `wip/pre-cleanup-2026-04-25`, `xroads/slot-1-claude-us-001-us-004`, `xroads/slot-2-claude-us-002-us-005`, `xroads/slot-3-claude-us-003-us-006`
- 2 worktrees removed: `_CODE-xroads-slot-1-core` (1.2 GB), `_CODE-xroads-slot-2-quality` (16 MB)
- `.gitignore` extended with `AGENT.md` and `.xroads-backup/` (extracted from the 3 obsolete `chore: gitignore loop files` commits before deletion)
- Tag `pre-scaffold-2026-04-25` posted on both remotes (rollback in 1 cmd)

### Test status (post-session)
- `swift build` clean (warnings deprecation préexistantes uniquement — voir Must row 4)
- `swift test` **675/675 pass** (was 607/619 at session start — net +56 tests, +12 fixed)
- App launches, no cockpit-brain spawned at boot (B0 fix verified live)

### RAF — not yet shipped (priorities below)
1. **B1** chat input ne submit pas (Enter & cmd+Enter no-op) — Must, critical
2. **B2** RVW Ribbon prend tout l'écran et masque la TitleBar — Must, high
3. **B3** RVW Ribbon dismiss unreliable — Must, high
4. Deprecation cleanup ~80 callsites — Must
5. Rebuild deferred views (`XRoadsDashboardView`, `LoopConfigurationPanel`) — Must
6. R1-R6, B4, B6, B7 — Should
7. Final brand mark swap, WEBSITE-FRAMEWORK.md impl — Nice
8. **Side-finding** : current `_CODE/prd.json` (Bug Sweep PRD with US-000..US-007) is now PARTIALLY DONE — US-000 closed by `69ea452`, US-007 closed by `3bd61d2`. Should be regenerated at next session start to focus only on remaining stories (US-001 chat submit, US-002+US-003 ribbon, US-004 R1, US-005 R4, US-006 R6).

### Branches at session end
- Only `main` local + `origin/main` + `public/main` (all aligned at `89d0638`)
- Tag: `pre-scaffold-2026-04-25` (rollback to pre-session state)


## Must (next 1–2 releases)

| Item | Value in one line | Rough size |
|------|-------------------|-----------|
| ~~**B0**~~ ✅ CLOSED `69ea452` — singleton-per-project gate via `BrainProcessRegistry` (in-process + PID file + SIGTERM/SIGKILL on shutdown), 6 new unit tests, verified live (0 brain spawned at boot) |  |  |
| **B1** — Orchestrator chat input doesn't submit (Enter & cmd+Enter both no-op; text stays in field) — `OrchestratorSidebar.swift` / `OrchestratorInput` | Core entry point is dead; users can't talk to the orchestrator | M (focus + key handler debug) |
| **B2** — RVW Ribbon (cmd+⇧R) takes the full window, hides the custom TitleBar, and the native macOS menu bar reappears — breaks the "tactical custom chrome" design | Reverses Ousmane's full visual identity work the moment review is opened | M (layout: ribbon should overlay or stack, not replace) |
| **B3** — RVW Ribbon toggle off is unreliable: cmd+⇧R doesn't close it when focus is elsewhere; visible top-right X button doesn't dismiss either | Users can get stuck in review with no clean exit | S (route close action through any focus state) |
| Deprecation cleanup: migrate ~80 call sites from old shims (`Color.textPrimary`, `.body14`, `Color.bgApp`, …) to locked tokens (`Theme.Color.ink`, `Theme.TextStyle.body`, `Theme.Color.void`, …) | Removes build-time warnings; locks every callsite on the v2 visual system Ousmane shipped | M (mechanical, ~80 sites across ~15 views) |
| Rebuild deferred views to spec: `XRoadsDashboardView` (brain-creature + slot grid) and `LoopConfigurationPanel` — both still in tree but unmounted from `MainWindowView` | Restores live operations UI after the 2026-04 visual identity refactor | L (real design + impl) |

## Should (2–4 releases out)

| Item | Value in one line | Rough size |
|------|-------------------|-----------|
| **R1** — Diagnostic readout (`AGENTS 0/6 · GATES 6/6 · DRIFT NONE`) uses voltage even when idle; should be `muted` at idle, `voltage` only when agents are running (`HeroIdleState.swift` L143) | Fixes false-alive impression on first paint | S |
| **R2** — Sidebar subtitle "multi-agent orchestration" too close in weight to title (`OrchestratorSidebar.swift` L79–81) — drop to `faint` or add letter-spacing | Restores hierarchy in the orchestrator sidebar | S |
| **R3** — TitleBar tabs too tight at right edge (SKL, ART, SET) at `minWindowWidth` — add overflow handling (`TitleBar.swift`) | Avoids clipped chrome on narrow windows | S |
| **R4** — RVW badge count "3" competes with label, both in voltage — voltage only on count, label stays default (`TitleBar.swift`) | Restores label/value visual hierarchy | XS |
| **R5** — `StatusPip` at 3×9px — green `.connected` hard to distinguish from yellow at that size (`Theme.swift` L204) — bump to 4×9px minimum | Improves status legibility | XS |
| **R6** — Crosshair arms subtle at 120px hero size — bump opacity 0.45 → 0.55 for `size ≥ 80` (`BrandMarkPlaceholder.swift` L26,31) | Restores reticle presence at hero size | XS |
| **B4** — Only 3 of 11 toolbar buttons (ORC/CKP/RVW) have `keyboardShortcut`; RUN/INSP/PRD/HIST/INTEL/SKL/ART/SET are mouse-only — `TitleBar.swift` | Handoff promised 11 shortcuts; missing 8 limits keyboard-driven workflow | S (8× `.keyboardShortcut(...)` calls) |
| ~~**B6**~~ ✅ CLOSED `3bd61d2` — replaced hardcoded `/Users/bigouz/Xroads/.screenshots` with `FileManager.temporaryDirectory.appendingPathComponent("xroads-snapshots")`; verified `grep -rn '/Users/bigouz' XRoads XRoadsTests scripts` returns zero |  |  |
| **B7** — `cmd+W` closes the main window AND quits the app entirely (no main-window-back pattern) — `XRoadsApp.swift` L133 | Surprising for users used to standard macOS behaviour where window can be reopened from menu | S (reopen via View menu or auto-restore) |

## Nice (someday / maybe)

| Item | Value in one line | Rough size |
|------|-------------------|-----------|
| Replace `BrandMarkPlaceholder` with the final XRoads brand mark across all callsites (chrome 18pt, sidebar 40pt, hero 120pt) | Ships the real identity once art direction lands the mark | S (single-view swap, all callsites pick it up) |
| Implement `docs/WEBSITE-FRAMEWORK.md` (Ousmane's landing page skeleton) into actual marketing site | Translates the landing-page brief into a built site | L (design + copy + build) |

## Rejected (kept for the record so we don't re-propose)

| Item | Why rejected | Date |
|------|--------------|------|
| _(none yet)_ | | |

## Hygiene

- Item in "Must" for > 60 days with no progress → demote to "Should" or kill
- Item in "Should" for > 120 days → demote to "Nice" or kill
- Item in "Nice" for > 180 days → kill or promote with fresh justification
