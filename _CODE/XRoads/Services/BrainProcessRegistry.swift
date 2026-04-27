import Foundation
import os

// MARK: - BrainProcessRegistry
//
// Singleton-per-project gate for the cockpit-brain headless subprocess.
// Persists the OS PID of the live brain on disk so that:
//   1. A second startCockpitBrain call on the same project is refused while one is alive (in-process safety net is in CockpitViewModel; this is the cross-restart layer).
//   2. After an app crash/restart, leftover brain processes are detected, terminated, and cleaned up before a new spawn proceeds.
//
// Storage: ~/Library/Application Support/XRoads/brain-<sha256(projectPath)-prefix12>.pid
//
// File format: a single line containing the decimal PID.
//
// Liveness check: kill(pid, 0) — POSIX semantics, no signal sent, only EPERM/ESRCH inspection.

actor BrainProcessRegistry {

    private let logger = Logger(subsystem: "com.xroads", category: "BrainRegistry")
    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directoryURL = appSupport.appendingPathComponent("XRoads", isDirectory: true)
        }
    }

    // MARK: - Public API

    /// Returns the PID of an alive brain registered for `projectPath`, or nil if none.
    /// Stale entries (PID dead) are cleaned up as a side effect.
    func aliveExistingPid(forProject projectPath: String) -> pid_t? {
        let url = pidFileURL(forProject: projectPath)
        guard let pid = readPidFile(at: url) else { return nil }

        if processIsAlive(pid: pid) {
            return pid
        }

        // Stale entry — clean up
        try? fileManager.removeItem(at: url)
        logger.info("Cleaned stale PID file for project (pid \(pid) was dead)")
        return nil
    }

    /// Records the PID of a freshly spawned brain. Overwrites any prior file.
    func register(pid: pid_t, forProject projectPath: String) throws {
        try ensureDirectoryExists()
        let url = pidFileURL(forProject: projectPath)
        let payload = "\(pid)\n"
        try payload.write(to: url, atomically: true, encoding: .utf8)
        logger.info("Registered brain pid \(pid) for project (file: \(url.lastPathComponent))")
    }

    /// Removes the PID file for a project (no signal sent).
    func clear(forProject projectPath: String) {
        let url = pidFileURL(forProject: projectPath)
        try? fileManager.removeItem(at: url)
    }

    /// Sends SIGTERM to the registered PID, waits up to `gracePeriod` for exit, then SIGKILL.
    /// Removes the PID file on success.
    /// No-op if no live PID is registered.
    func terminateAndClear(
        forProject projectPath: String,
        gracePeriod: TimeInterval = 5.0
    ) async {
        let url = pidFileURL(forProject: projectPath)
        guard let pid = readPidFile(at: url) else { return }

        guard processIsAlive(pid: pid) else {
            try? fileManager.removeItem(at: url)
            return
        }

        // SIGTERM
        let termResult = kill(pid, SIGTERM)
        if termResult != 0 {
            logger.warning("SIGTERM to \(pid) returned errno \(errno)")
        }

        // Wait up to gracePeriod, polling every 100ms
        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !processIsAlive(pid: pid) {
                try? fileManager.removeItem(at: url)
                logger.info("Brain pid \(pid) terminated cleanly via SIGTERM")
                return
            }
        }

        // SIGKILL
        _ = kill(pid, SIGKILL)
        // Brief settle
        try? await Task.sleep(nanoseconds: 100_000_000)
        try? fileManager.removeItem(at: url)
        logger.warning("Brain pid \(pid) did not exit within \(gracePeriod)s — sent SIGKILL")
    }

    /// Sweeps the registry directory and removes any PID file whose PID is no longer alive.
    /// Call at app startup to clean leftovers from previous crashes.
    /// Returns the count of stale files removed.
    @discardableResult
    func cleanStalePidFiles() -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return 0
        }
        var cleaned = 0
        for url in entries where url.lastPathComponent.hasPrefix("brain-") && url.pathExtension == "pid" {
            if let pid = readPidFile(at: url), processIsAlive(pid: pid) {
                continue
            }
            try? fileManager.removeItem(at: url)
            cleaned += 1
        }
        if cleaned > 0 {
            logger.info("Cleaned \(cleaned) stale brain PID file(s) at startup")
        }
        return cleaned
    }

    // MARK: - Internals

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    /// SHA-256 prefix-12 of the project path. Stable across platforms.
    /// Implemented without CryptoKit so it stays available pre-macOS 10.15 if the SDK floor moves.
    private func projectKey(_ projectPath: String) -> String {
        let absolute = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        var hash = UInt64(14_695_981_039_346_656_037)  // FNV-1a 64-bit offset basis
        for byte in absolute.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        // 12-hex-char digest, deterministic, collision risk negligible for the small N of projects per user
        return String(format: "%012llx", hash)
    }

    private func pidFileURL(forProject projectPath: String) -> URL {
        directoryURL.appendingPathComponent("brain-\(projectKey(projectPath)).pid")
    }

    private func readPidFile(at url: URL) -> pid_t? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(trimmed), pid > 0 else { return nil }
        return pid
    }

    /// kill(pid, 0): true iff the PID exists and we have permission to signal it (we always do for our own children).
    nonisolated private func processIsAlive(pid: pid_t) -> Bool {
        let result = kill(pid, 0)
        if result == 0 { return true }
        // EPERM means the PID exists but we cannot signal it — still alive
        if errno == EPERM { return true }
        return false
    }
}
