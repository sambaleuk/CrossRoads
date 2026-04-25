# Contributing to XRoads

Thank you for your interest in contributing to XRoads!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/CrossRoads.git`
3. Create a branch: `git checkout -b feat/my-feature`
4. Make your changes
5. Build and test: `swift build && swift test`
6. Commit and push
7. Open a Pull Request

## Development Setup

- **macOS 14.0+** (Sonoma)
- **Swift 5.9+**
- **Xcode 15+** (optional, for GUI)
- **Node.js 18+** (for MCP server)

```bash
swift build
swift run XRoads
swift test
```

## Code Style

- Use Swift's native async/await and actors for concurrency
- Follow existing patterns in the codebase
- Keep views small, extract reusable components
- Document public APIs with `///` comments

## What to Contribute

- **Bug fixes** — always welcome
- **New agent integrations** — add support for more AI coding tools
- **UI improvements** — better visualizations, accessibility
- **Documentation** — tutorials, guides, translations
- **Tests** — increase coverage

## What NOT to Contribute

- Changes to the intelligence/brain layer (Pro features)
- Unrelated refactoring without discussion
- Dependencies without justification

## Pull Request Process

1. Ensure your code builds without warnings
2. Update documentation if needed
3. Add tests for new functionality
4. Keep PRs focused — one feature/fix per PR
5. Write clear commit messages explaining WHY

## Reporting Issues

Use GitHub Issues. Include:
- XRoads version
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Logs if available

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
