# Backlog — crossroads swift

Everything not in `next-release.md`. Ordered by priority within each bucket.

## Must (next 1–2 releases)

| Item | Value in one line | Rough size |
|------|-------------------|-----------|
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
