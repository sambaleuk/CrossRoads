# XRoads

**Give it a PRD. Get code on main.**

Native macOS app that runs 6 AI coding agents in parallel on your codebase. Each agent gets its own git worktree, its own branch, its own PTY terminal. They write code, run tests, and XRoads merges everything back. You review the PR.

No configuration theater. No AI org charts. No "CEO agent delegates to CTO agent." Just code shipped while you sleep.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)

---

## What it actually does

1. You load a PRD (list of user stories with dependencies)
2. XRoads figures out which stories can run in parallel (dependency-aware layers)
3. It spins up Claude, Gemini, or Codex agents in isolated git worktrees
4. Each agent writes code, runs tests, reports progress via real PTY
5. When a layer finishes, XRoads merges and starts the next
6. You get a branch with working code. Merge it.

**The only metric that matters: stories shipped per hour.**

---

## What makes it different

### It ships code, not dashboards

Real PTY execution via macOS `script` command. Real `claude --dangerously-skip-permissions`. Real git worktrees with real merges. The output isn't a Notion board of AI tasks — it's code on a branch with passing tests.

### It learns from your codebase

After each run, XRoads trains ML models locally (LinearRegression, NaiveBayes, DecisionTree). Which agent is fastest on Rust backend stories? Which model is cheapest for simple UI work? Next time, routing is automatic.

### It prevents problems before they happen

Before dispatching two agents to overlapping files, predicts the merge conflict and resequences. Before an agent runs `rm -rf` or `DROP TABLE`, suspends the process via SIGSTOP and asks you. Immutable audit trail on every dangerous operation.

### 52+ Swift actors for thread safety

Every service is an actor. No locks, no data races, no "it works on my machine." Built on Swift structured concurrency with TaskGroup for parallel dispatch.

---

## Quick Start

```bash
swift build
swift run XRoads

# Or with Xcode
xcodebuild -scheme XRoads -destination 'platform=macOS' build
```

---

## How it works

```
Your PRD ──► Layer Builder ──► Conflict Check ──► Parallel Dispatch
                                                       │
                                          ┌────────────┼────────────┐
                                          ▼            ▼            ▼
                                      Slot 0       Slot 1       Slot 2
                                    claude PTY   gemini PTY   codex PTY
                                    feat/api     feat/ui      feat/tests
                                          │            │            │
                                          └────────────┼────────────┘
                                                       ▼
                                                 Merge & Next
                                                       │
                                                       ▼
                                                 Code on main.
```

---

## Safety

13 dangerous patterns scanned on every PTY output line. Process frozen via SIGSTOP until you approve. Immutable audit on every gate decision.

`rm -rf`, `git push --force`, `DROP TABLE`, `chmod 777`, `curl | bash`, `sudo`, `kill -9`, and 6 more.

---

## Intelligence

3 ML models train locally after each orchestration. Zero cloud. Zero data exfiltration.

- **Time estimation** — LinearRegression predicts how long each story will take
- **Task categorization** — NaiveBayes classifies stories (backend_rust, frontend_react, testing, etc.)
- **Conflict prediction** — DecisionTree predicts which stories will conflict
- **Persistent memory** — "Claude struggled with TS generics last week. Route to Gemini."
- **Trust scoring** — 94% pass rate on React? Auto-merge to staging.
- **Cost-aware routing** — Budget tight? Sonnet. Story complex? Opus. Automatic.

---

## The numbers

| Metric | Value |
|--------|-------|
| Swift actors | 52+ |
| GRDB tables | 21 |
| LOC | 66,000+ |
| ML models | 3 (pure Swift math, zero frameworks) |
| Agent scripts | nexus-loop, gemini-loop, codex-loop |
| Platform | macOS 14+ (Sonoma), Apple Silicon optimized |

---

## What we don't do

- **No fake AI org charts.** AI isn't a company with a CEO.
- **No setup porn.** Open the app, load a PRD, agents ship code.
- **No cloud ML.** Everything trains on your machine.
- **No pretending agents are autonomous.** They write code. You review it.

---

## Cross-platform

- **macOS**: This repo (native SwiftUI)
- **Windows/Linux/macOS**: [CrossRoads-Tauri](https://github.com/sambaleuk/CrossRoads-Tauri) (Tauri + React + Rust)

Same features, same agent scripts, same ML models.

---

## Contributing

```bash
swift build    # Build
swift test     # Test
swift run XRoads  # Run
```

The bar: does it help ship code faster?

---

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.

---

Built by [Neurogrid](https://neurogrid.me) — Open source under Apache 2.0.
