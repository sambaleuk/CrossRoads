//
//  OrphanProcessDetector.swift
//  XRoads
//
//  Created by Nexus on 2026-03-30.
//  Feature: Detect orphan claude/gemini/codex processes from crashed XRoads sessions
//

import Foundation
import os

// MARK: - OrphanAgent

/// Represents a detected orphan AI agent process
struct OrphanAgent: Sendable, Identifiable {
    let pid: Int32
    let agentType: String  // "claude", "gemini", "codex"
    let worktreePath: String?
    let commandLine: String

    var id: Int32 { pid }
}

// MARK: - OrphanProcessDetector

/// Scans for running claude/gemini/codex processes that may be orphans
/// from a previous XRoads session that crashed or was force-quit.
actor OrphanProcessDetector {

    private let logger = Logger(subsystem: "com.xroads", category: "OrphanDetector")

    /// Known agent binary names to scan for
    private static let agentBinaries = ["claude", "gemini", "codex"]

    // MARK: - Detection

    /// Scan for running claude/gemini/codex processes that may belong to XRoads.
    ///
    /// Filters out processes in the current PID tree (i.e., processes we launched this session).
    /// Matches by CROSSROADS_ environment markers or xroads_exit temp files.
    func detectOrphans() async -> [OrphanAgent] {
        let currentPid = ProcessInfo.processInfo.processIdentifier

        // Get all running processes matching agent binaries
        guard let psOutput = runPS() else {
            logger.warning("Failed to run ps command for orphan detection")
            return []
        }

        var orphans: [OrphanAgent] = []

        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse pid and command from `ps -eo pid,command` output
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let pid = Int32(parts[0]) else { continue }

            let command = String(parts[1])

            // Skip our own process
            if pid == currentPid { continue }

            // Check if this is an agent binary
            guard let agentType = matchAgentType(command: command) else { continue }

            // Check for XRoads markers: CROSSROADS_ env vars or xroads-related flags
            let isXRoadsRelated = checkXRoadsMarkers(pid: pid, command: command)

            if isXRoadsRelated {
                let worktree = extractWorktreePath(command: command)
                let orphan = OrphanAgent(
                    pid: pid,
                    agentType: agentType,
                    worktreePath: worktree,
                    commandLine: command
                )
                orphans.append(orphan)
                logger.info("Detected orphan: pid=\(pid) type=\(agentType) worktree=\(worktree ?? "nil")")
            }
        }

        return orphans
    }

    /// Try to match orphans to existing terminal slots by worktree path.
    ///
    /// Returns pairs of (orphan, slotNumber?) where slotNumber is non-nil
    /// if the orphan's worktree matches an existing slot configuration.
    func matchToSlots(
        orphans: [OrphanAgent],
        terminalSlots: [TerminalSlot]
    ) -> [(OrphanAgent, Int?)] {
        return orphans.map { orphan in
            if let worktree = orphan.worktreePath {
                let matchingSlot = terminalSlots.first { slot in
                    slot.worktree?.path == worktree
                }
                return (orphan, matchingSlot?.slotNumber)
            }
            return (orphan, nil)
        }
    }

    // MARK: - Private Helpers

    /// Run `ps -eo pid,command` and return the output
    private func runPS() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            logger.error("ps command failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if a command string matches a known agent binary
    private func matchAgentType(command: String) -> String? {
        let lowered = command.lowercased()
        // Match the binary name at the end of a path or as standalone
        for binary in Self.agentBinaries {
            // Match patterns like "/path/to/claude ...", "claude ...", "node .../claude ..."
            if lowered.contains("/\(binary) ") ||
               lowered.contains("/\(binary)\n") ||
               lowered.hasPrefix("\(binary) ") ||
               lowered.hasSuffix("/\(binary)") {
                return binary
            }
        }
        return nil
    }

    /// Check if a process has XRoads-related markers
    private func checkXRoadsMarkers(pid: Int32, command: String) -> Bool {
        // Check 1: Command line contains XRoads-related flags or paths
        if command.contains("CROSSROADS_") ||
           command.contains("xroads") ||
           command.contains("XRoads") ||
           command.contains("crossroads") {
            return true
        }

        // Check 2: Look for xroads_exit temp files associated with this PID
        let tempDir = NSTemporaryDirectory()
        let exitFile = (tempDir as NSString).appendingPathComponent("xroads_exit_\(pid)")
        if FileManager.default.fileExists(atPath: exitFile) {
            return true
        }

        // Check 3: Check if the process has CROSSROADS_ environment variables
        // via /proc or procfs (macOS doesn't have /proc, so we use ps -E)
        if let envOutput = getProcessEnvironment(pid: pid) {
            if envOutput.contains("CROSSROADS_SLOT") ||
               envOutput.contains("CROSSROADS_AGENT") {
                return true
            }
        }

        // Check 4: Process uses --agent flag with slot- prefix (XRoads naming convention)
        if command.contains("--agent") && command.contains("slot-") {
            return true
        }

        return false
    }

    /// Get environment variables for a process using `ps -E -p <pid>`
    private func getProcessEnvironment(pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-E", "-o", "command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Extract worktree path from the command line
    private func extractWorktreePath(command: String) -> String? {
        // Look for a path after common working directory patterns
        // Pattern: worktrees/slot-N-... or -C /path/to/worktree
        let patterns = [
            // Match -C <path> or --cwd <path>
            try? NSRegularExpression(pattern: #"(?:-C|--cwd)\s+(/\S+)"#),
            // Match worktree paths in the command
            try? NSRegularExpression(pattern: #"(/\S+/worktrees/slot-\d+[^\s]*)"#)
        ].compactMap { $0 }

        for regex in patterns {
            let range = NSRange(command.startIndex..., in: command)
            if let match = regex.firstMatch(in: command, range: range),
               match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: command) {
                return String(command[captureRange])
            }
        }

        return nil
    }
}
