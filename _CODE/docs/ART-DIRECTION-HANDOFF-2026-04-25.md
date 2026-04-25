# XRoads — Full Session Handoff · 2026-04-25
> For: Birahim & agents · Build: ✅ clean · 14 files changed, 1962+ insertions

---

## TL;DR

Today we rebuilt the entire front-end shell of XRoads to match the v2 design spec. The old system toolbar, OrchestratorChatView sidebar, XRoadsDashboardView center, and LoopConfigurationPanel bottom were all replaced with a locked visual system: custom TitleBar, HeroIdleState, OrchestratorSidebar, StatusBar, and BottomBar. Then we ran a visual audit and fixed 7 polish issues. Everything compiles, everything runs.

---

## Commit Log (chronological)

All commits are on `main` and pushed to `origin/main`.

| # | Hash | Message | Files | +/- |
|---|------|---------|-------|-----|
| 1 | `2896598` | feat: ground visual identity, locked tokens and motion library | 3 | +539 / -293 |
| 2 | `27dd9a1` | feat: tactical title bar with brand mark placeholder and toolbar | 5 | +426 / -108 |
| 3 | `9babe37` | feat: central hero idle state with HUD frame and diagnostic readout | 3 | +187 / -17 |
| 4 | `10bcc54` | feat: orchestrator sidebar idle state with brand, suggestion pills, input | 3 | +228 / -1 |
| 5 | `4817831` | feat: top status bar and bottom status strip | 4 | +217 / -9 |
| 6 | `dc14aad` | fix: orchestrator input snapshot path skips real TextField | 1 | +10 / -5 |
| 7 | `a281724` | chore: update Package.resolved and add website framework doc | 2 | +368 |
| 8 | **uncommitted** | art direction polish — 7 fixes (see Section 4) | 5 | +71 / -22 |

---

## Section 1: Visual Identity Foundation (commit `2896598`)

**What:** Complete refactor of `Theme.swift` from the old token system to the v2 locked visual system. Created `Motion.swift` from scratch.

### Theme.swift — `XRoads/Resources/Theme.swift`

**Locked color palette (7 tokens — the ONLY colors to use):**

| Token | Hex | When to use |
|-------|-----|-------------|
| `Theme.Color.void` | `#09090B` | Deepest background, app canvas |
| `Theme.Color.surface` | `#131316` | Cards, panels, elevated surfaces |
| `Theme.Color.rule` | `#1C1C20` | 0.5pt border lines, separators |
| `Theme.Color.ink` | `#E5E5E7` | Primary text, titles |
| `Theme.Color.muted` | `#8A8A92` | Secondary text, labels, idle states |
| `Theme.Color.faint` | `#4A4A52` | Tertiary text, disabled, placeholders |
| `Theme.Color.voltage` | `#FFD60A` | Active states, live data, interactive accents |

**Typography (2 font families):**
- `Theme.Font.displayRegular(size)` / `Theme.Font.displayMedium(size)` → InterTight
- `Theme.Font.mono(size)` → JetBrainsMono-Regular
- Preset styles: `heroDisplay` (56pt), `pageHeading` (28pt), `sectionHead` (18pt), `bodyLarge` (16pt), `body` (14pt), `smallBody` (12pt), `labelMono` (11pt), `tacticalMono` (10pt)

**Layout primitives:**
- `radiusFlat = 0` — no rounded corners anywhere
- `radiusTactile = 2` — rare minimal rounding
- `ruleWidth = 0.5` — all strokes and separators

**StatusPip component** (lines 191–231): A 3×9pt rectangle status indicator with states: `.idle`, `.queued`, `.active`, `.connected`, `.error`. Colors: faint (idle/queued), voltage (active/error), neon-green #3FB950 (connected). Live states pulse via `Motion.pulsePip`.

**Deprecated shims preserved** (lines 233+): All old `Color.textPrimary`, `Color.bgApp`, `.body14` etc. are preserved as `@available(*, deprecated)` shims routing to the closest locked token. They compile but emit warnings. See Section 5 for the full migration inventory.

### Motion.swift — `XRoads/Resources/Motion.swift` (NEW — 170 lines)

All animation constants centralized here. Key constants:
- `pulseStroke` — repeating 2.4s ease for stroke animations
- `breatheDot` — repeating 3.5s ease for dot/pip breathing
- `pulsePip` — repeating 1.2s ease for status pips
- `cursorBlink` — repeating 0.6s ease for cursor visibility
- `shimmerBar` — repeating 0.8s ease for progress bar indicators
- `scanlineTravel` — 12s linear one-shot for HUD scanline
- `bracketPulse` — repeating 4s ease for HUD bracket corners
- `diagTick` — 0.3s ease-out for diagnostic readout reveal
- `tacticalHover` — 0.12s ease-out for hover state transitions

Also contains `BracketCorner` (Shape) and `HUDFrame` (View) — the crop-mark corner brackets used in HeroIdleState.

---

## Section 2: UI Shell Components (commits `27dd9a1` → `4817831`)

### TitleBar.swift — `XRoads/Views/Components/TitleBar.swift` (NEW — 299 lines)

**Replaces:** System `.toolbar` — the native macOS toolbar is gone.

**Architecture:**
- Window style changed to `.hiddenTitleBar` in `XRoadsApp.swift` (line 39)
- 30pt custom chrome strip, surface background, 0.5pt rule bottom border
- 90pt left clearance for native macOS traffic lights (red/yellow/green dots)
- Brand mark (18pt `BrandMarkPlaceholder`) + "xroads" wordmark
- Right edge: suite switcher dropdown ("developer" chevron) + 11 toolbar icon-buttons

**Toolbar buttons (left to right):** ORC, CKP, RVW, RUN, INSP, PRD, HIST, INTEL, SKL, ART, SET

Each button: SF Symbol + mono caps label, faint at rest, ink on hover, voltage when active. Keyboard shortcuts (cmd-shift-O, cmd-shift-C, etc.) attached at button level.

**Important note:** Uses `Button + .popover` pattern instead of `Menu` because `Menu` under `ImageRenderer` falls back to system popup chrome that ignores `.menuStyle(.borderlessButton)`. This is the required pattern for all overlay menus/popovers.

**RVW badge count "3"** — currently uses voltage color for both label and count. Known issue: needs hierarchy separation (see Section 4 remaining items).

### HeroIdleState.swift — `XRoads/Views/Components/HeroIdleState.swift` (NEW — 193 lines)

**Replaces:** `XRoadsDashboardView` mount in center column.

**Composites:**
- Void background filling the column
- `HUDFrame` — crop-mark bracket corners at four edges, pulsing via `Motion.bracketPulse`
- `CoordinateCallouts` — mono 9pt faint text at four margins: `X:0 Y:0`, `{width}×{height}`, `T+00:00:00`, `Q:0`
- Horizontal scanline (splits into two segments gapping around the brand mark — 140px gap)
- `BrandMarkPlaceholder(size: 120)` — centered crosshair reticle
- "SYSTEM IDLE" — labelMono, muted color (quiet)
- `DiagnosticReadout` — `AGENTS 0/6 · GATES 6/6 · DRIFT NONE` with staggered reveal animation (0s, 1s, 2s)
- "what are we shipping?" — mono 12pt faint with blinking voltage cursor

**Snapshot support:** `snapshotScanlineSeed` parameter allows test target to seed the scanline position since `ImageRenderer` doesn't fire `.onAppear`.

**The old `XRoadsDashboardView` is NOT deleted.** It remains in the codebase but is no longer mounted from `MainWindowView`. It contains the brain-creature view and non-conformant slot grid that both need a spec-aligned rebuild later.

### OrchestratorSidebar.swift — `XRoads/Views/Components/OrchestratorSidebar.swift` (NEW — 222 lines)

**Replaces:** `OrchestratorChatView` mount in left column.

**Composites:**
- "ORCHESTRATOR" header with `.connected` StatusPip (green) + "API" label
- `BrandMarkPlaceholder(size: 40)` centered
- "xroads orchestrator" (InterTight Medium 13pt ink) / "multi-agent orchestration" (InterTight Regular 10pt muted)
- TRY section with 3 `SuggestionPill` buttons: mono 11pt, 0.5pt faint border, voltage on hover
- `OrchestratorInput` at bottom: "INPUT" label, "what are we building today?" placeholder with blinking voltage cursor, 0.5pt rule underline (voltage when focused)

**Snapshot support:** `snapshotCursorOn` parameter freezes cursor visibility for headless rendering. The real `TextField` only mounts when `cursorOverride == nil` (production path) because `ImageRenderer` renders `TextField` with system chrome.

### StatusBar.swift — `XRoads/Views/Components/StatusBar.swift` (NEW — 122 lines)

Top of center column. 30pt, surface background, 0.5pt rule bottom.
- StatusPip + label (default: "READY")
- Free-text status (default: "standing by")
- `ProgressShimmer`: 80×4pt rail, voltage fill, 2pt indicator that pulses via `Motion.shimmerBar`
- Percentage + agent counter

### BottomBar.swift — `XRoads/Views/Components/BottomBar.swift` (NEW — 62 lines)

Window footer. 26pt, surface background, 0.5pt rule top + bottom.
- Section name in mono caps faint (default: "ACTIVE PROJECT")
- Counter + 6pt dot: voltage when healthy, faint when dormant

### BrandMarkPlaceholder.swift — `XRoads/Views/Components/BrandMarkPlaceholder.swift` (NEW — 56 lines)

Typed sentinel for the final brand mark. Yellow-stroked square with crosshair reticle inside (horizontal + vertical arms at 45% opacity, center dot at 70%). Parameterized `size` for chrome (18pt), sidebar (40pt), and hero (120pt) contexts. **When the final mark ships, swap the body of this one view and every callsite updates.**

---

## Section 3: MainWindowView Rewiring

**File:** `XRoads/Views/MainWindowView.swift` — net -176 lines (heavy deletions of old layout)

**What changed:**
1. Removed `.toolbar { toolbarContent }` — replaced by `TitleBar` component
2. Left column: `OrchestratorChatView()` → `OrchestratorSidebar()`
3. Center column: `XRoadsDashboardView(...)` → `VStack { StatusBar(), HeroIdleState() }`
4. Bottom: `LoopConfigurationPanel` → `BottomBar()`
5. All the old binding wiring for `dashboardMode`, `terminalSlots`, `orchestratorVisualState` removed from the center mount

**XRoadsApp.swift change:** `.windowStyle(.automatic)` → `.windowStyle(.hiddenTitleBar)` — this is what makes the custom title bar work.

---

## Section 4: Art Direction Polish (uncommitted — 7 fixes)

These are the **uncommitted changes** sitting on top of `a281724`. They need to be committed.

| # | Fix | File | Line(s) |
|---|-----|------|---------|
| 1 | Brand mark: empty square → crosshair reticle (arms + center dot) | `BrandMarkPlaceholder.swift` | 9–40 |
| 2 | "what are we shipping?" from proportional Inter → monospace JetBrains + blinking cursor | `HeroIdleState.swift` | 76–85, 19, 103–105 |
| 3 | "SYSTEM IDLE" color from voltage (yellow) → muted (gray) — idle should feel quiet | `HeroIdleState.swift` | 68 |
| 4 | Scanline split into 2 segments that gap around brand mark (140px gap) | `HeroIdleState.swift` | 38–60 |
| 5 | Suggestion pill default border bumped from `rule` → `faint` for visibility | `OrchestratorSidebar.swift` | 141 |
| 6 | API pip changed from `.active` (yellow) → `.connected` (green #3FB950) | `OrchestratorSidebar.swift` 58, `Theme.swift` 194,216,222 |
| 7 | Bottom bar: added bottom 0.5pt rule for row separation when stacked | `BottomBar.swift` | 42–46 |

### Remaining issues (NOT fixed — for follow-up)

| # | Issue | File | Detail |
|---|-------|------|--------|
| R1 | Diagnostic values (`0/6`, `6/6`, `NONE`) use voltage-yellow even in idle | `HeroIdleState.swift` L143 | Should be `muted` when idle, `voltage` only when agents are running |
| R2 | Sidebar subtitle "multi-agent orchestration" too close in weight to title | `OrchestratorSidebar.swift` L79–81 | Drop to `faint` color or add letter-spacing |
| R3 | TitleBar tabs too tight at right edge (SKL, ART, SET) | `TitleBar.swift` | Verify at `minWindowWidth`, may need overflow |
| R4 | RVW badge count "3" competes with label — both in voltage | `TitleBar.swift` | Use voltage only on count, not label |
| R5 | StatusPip at 3×9px — green `.connected` hard to distinguish from yellow | `Theme.swift` L204 | Consider 4×9px minimum |
| R6 | Crosshair arms subtle at 120px hero size | `BrandMarkPlaceholder.swift` L26,31 | Bump opacity from 0.45 → 0.55 for size ≥ 80 |

---

## Section 5: Snapshot Tests

**File:** `XRoadsTests/SnapshotTests.swift` (NEW — 103 lines)

Uses `ImageRenderer` at scale 4× for inspect-grade detail. Replaces screencapture-based validation since CLI sessions don't hold Screen Recording permission.

Tests cover: TitleBar, HeroIdleState, OrchestratorSidebar, StatusBar, BottomBar.

**Key pattern:** Components expose `snapshot*` parameters (e.g., `snapshotScanlineSeed`, `snapshotCursorOn`, `snapshotShimmerOn`) that freeze animated state for deterministic rendering. The running app passes `nil` for these and drives animation through `@State` + `.onAppear`.

---

## Section 6: Website Framework Document

**File:** `docs/WEBSITE-FRAMEWORK.md` (NEW — 359 lines)

Structural skeleton for the XRoads landing page. Defines:
- Section order and content blocks
- Visual treatment guidelines per section
- Typography and spacing rules
- Open decisions for copy and design finalization
- Strategic prerequisites for the copy agent

This is a **reference document** — no code implements it yet.

---

## Section 7: Legacy Deprecation Debt

The build emits deprecation warnings from files still using old shims. These are **pre-existing** — not caused by today's work. The shims route to locked tokens so everything works, but the warnings need cleanup.

### Migration mapping

| Old (deprecated) | New (locked) |
|---|---|
| `Color.textPrimary` | `Theme.Color.ink` |
| `Color.textSecondary` | `Theme.Color.muted` |
| `Color.textTertiary` | `Theme.Color.faint` |
| `Color.bgApp` / `Color.bgCanvas` | `Theme.Color.void` |
| `Color.bgSurface` / `Color.bgElevated` | `Theme.Color.surface` |
| `.body14` | `Theme.TextStyle.body` |

### Files needing migration

**Deprecated colors:** `ChatMessageView.swift` (6), `PRDProposalView.swift` (14), `SkillRowView.swift` (8), `SkillDetailSheet.swift` (14), `OrchestratorChatView.swift` (3+), `WorktreeCard.swift` (5), `MainWindowView.swift` (1)

**Deprecated `.body14`:** `ChatMessageView.swift`, `ChatInputBar.swift` (2), `OrchestratorChatView.swift`, `WorktreeCard.swift`, `GitDashboardView.swift` (2), `StartSessionSheet.swift`, `CommandPaletteView.swift` (2), `MainWindowView.swift` (2), `TerminalGridLayout.swift` (2), `WorktreeCreateSheet.swift` (5), `APIKeysSettingsView.swift` (2), `CLISettingsView.swift`, `MCPSettingsView.swift` (4)

---

## Section 8: Architecture Notes

### Pattern: ZStack overlays for contextual menus
Standard SwiftUI `.popover` and `Menu` cause `SIGSEGV` or fall back to system chrome under `ImageRenderer`. Use `Button + .popover` or `ZStack` overlay patterns instead.

### Pattern: Snapshot-safe animation
Components that animate on `.onAppear` expose a `snapshot*` parameter. When non-nil, the parameter freezes the animation state. When nil (production), `.onAppear` drives the animation.

### What's deferred (not mounted, still in codebase)
- `XRoadsDashboardView` — old brain-creature + slot grid. Needs spec-aligned rebuild.
- `OrchestratorChatView` — chat history view. Will be the active-state target when conversations are mounted.
- `LoopConfigurationPanel` — expand-to-configure UX. Deferred to sheet/popover in future commit.

---

## How to Build & Verify

```bash
cd /Users/bigouz/Xroads
swift build -c debug          # builds in ~15s
.build/debug/XRoads           # runs the app
```

**Visual checkpoints:**
1. Custom title bar (30pt) with traffic lights, brand mark, 11 toolbar buttons
2. Hero center: crosshair in yellow square, "SYSTEM IDLE" in gray, mono prompt with blinking cursor
3. Left sidebar: green API pip, visible pill borders, "INPUT" bar at bottom
4. Status bar at top of center column with progress shimmer
5. Bottom bar with rule separators between rows
