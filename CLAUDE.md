# CLAUDE.md — _CROSSROADS_SWIFT

Master instructions for Claude when working in this production repo.

---

## 1. Identity & Purpose

**Repo:** `_CROSSROADS_SWIFT`
**Category:** A — SaaS Product (native macOS, distributed app)
**Parent:** `03_PRODUCTION/`
**Operating entity:** NeuroGrid LLC (Wyoming)
**Stability tier:** A (macOS-native release — verify user count)

### What it is

XRoads — "Give it a PRD. Get code on main." Native macOS app that runs 6 AI coding agents in parallel on a codebase, each in its own git worktree + PTY. Agents write code, run tests, XRoads merges back. Swift implementation (macOS 14+, Swift 5.9+).

Companion product: `_CROSSROADS_TAURI` (cross-platform version). See also `_XROADS_LOOP` (shell scripts used by both).

## 2. Tech stack

- **Language:** Swift 5.9+
- **Platform:** macOS 14+ (native)
- **Build:** Swift Package Manager (`Package.swift`)
- **Distribution:** (TBD — Mac App Store / direct DMG / homebrew cask — confirm)
- **Dependencies:** `xroads-modragor-deps` (ajv + ajv-formats, for PRD JSON-schema validation)

## 3. Reference scaffold

Follows the 4-folder production scaffold — see `_ADSTAGER/CLAUDE.md`.

## 4. Capability declaration

### Allowed without asking

- Read any file
- Edit `_RESEARCH/**`, `_ROADMAP/**`, `_RETEX/**`, `_OPS/**`
- Add a new `_INCIDENTS/*.md` file

### Ask before

- Editing `_CODE/**` — production macOS app
- Editing `_COMPLIANCE/**`
- Building (`swift build`), signing, notarizing, or shipping a release
- Changing distribution channel

### Never

- Ship an unsigned / un-notarized build to users
- Commit developer certificates or signing keys
- Break the promise: each agent gets its own worktree (it's the structural guarantee of the product)

## 5. Workspace rules

- macOS code-signing + notarization is mandatory for distribution
- AI provider cost is per-user (runs on user's Anthropic key) — still document in `_OPS/cost.md` for the project's own test runs
- Append-only zones: `_INCIDENTS/`, `_COMPLIANCE/audit-log.md`

## 6. Inheritance

`03_PRODUCTION/CLAUDE.md` → `00_MAIN/CLAUDE.md`. Generic runbooks at `/07_INFRA/runbooks/`.

## 7. Compression layer

- Git-worktree-per-agent pattern (shared with `_CROSSROADS_TAURI`)
- PRD-driven agent orchestration
- Native macOS app shipping playbook (signing, notarization, update flow)

## 8. Preferences

- Swift-style main branch, release tags drive TestFlight / DMG
- CHANGELOG strict — breaking = major

## 9. Honesty clause

- "6 agents in parallel" is the current default — actual count is configurable, not a contract
- "Code shipped while you sleep" is aspirational marketing — users review the PR

## 10. Open questions for Birahim

1. Current distribution channel + download counts?
2. Relationship with `_CROSSROADS_TAURI`: Swift = flagship, Tauri = cross-platform port — or are we splitting investment?
3. Telemetry — opt-in, opt-out, or none?
4. Pricing model: free, paid, freemium?
