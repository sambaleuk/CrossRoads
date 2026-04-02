import Foundation

// MARK: - PathResolver

/// Centralized utility for resolving binary paths, NVM node versions,
/// and shell executables. Eliminates hardcoded paths throughout the app.
///
/// Usage:
///   PathResolver.findBinary("claude")     // → /Users/x/.nvm/versions/node/v22.13.0/bin/claude
///   PathResolver.nvmBinPath(for: "claude") // → NVM-specific lookup
///   PathResolver.shell                     // → /bin/zsh or /bin/bash (from SHELL env)
///   PathResolver.home                      // → /Users/x (via FileManager)
enum PathResolver {

    // MARK: - Home & Shell

    /// User's home directory (portable — uses FileManager, not NSHomeDirectory).
    static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// User's default shell (from SHELL env var, falls back to /bin/sh for POSIX compat).
    static var shell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
    }

    // MARK: - NVM Dynamic Resolution

    /// Find the latest NVM node bin directory (e.g. `~/.nvm/versions/node/v22.13.0/bin`).
    /// Globs all installed versions and picks the highest.
    static func latestNVMBinDir() -> String? {
        let nvmDir = (home as NSString).appendingPathComponent(".nvm/versions/node")
        guard FileManager.default.fileExists(atPath: nvmDir) else { return nil }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) else {
            return nil
        }

        let validVersions = entries
            .filter { $0.hasPrefix("v") }
            .compactMap { entry -> (binDir: String, version: [Int])? in
                let binDir = (nvmDir as NSString).appendingPathComponent(entry).appending("/bin")
                guard FileManager.default.fileExists(atPath: binDir) else { return nil }
                let parts = parseVersion(entry)
                guard !parts.isEmpty else { return nil }
                return (binDir, parts)
            }

        let sorted = validVersions.sorted { lhs, rhs in
            for (l, r) in zip(lhs.version, rhs.version) {
                if l != r { return l > r }
            }
            return lhs.version.count > rhs.version.count
        }

        return sorted.first?.binDir
    }

    /// Find a specific binary inside the latest NVM node bin directory.
    static func nvmBinPath(for binary: String) -> String? {
        guard let binDir = latestNVMBinDir() else { return nil }
        let path = (binDir as NSString).appendingPathComponent(binary)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: - General Binary Resolution

    /// Standard search paths for CLI tools (no hardcoded versions).
    static var standardSearchPaths: [String] {
        var paths: [String] = []

        // NVM (dynamic — latest version)
        if let nvmBin = latestNVMBinDir() {
            paths.append(nvmBin)
        }

        // User local
        paths.append("\(home)/.local/bin")
        paths.append("\(home)/bin")

        // Homebrew (ARM + Intel)
        paths.append("/opt/homebrew/bin")
        paths.append("/usr/local/bin")

        // System
        paths.append("/usr/bin")

        return paths
    }

    /// Build an enhanced PATH string with standard search paths prepended.
    static var enhancedPATH: String {
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        return standardSearchPaths.joined(separator: ":") + ":" + currentPath
    }

    /// Find a binary by name. Searches:
    /// 1. NVM bin directory (dynamic, latest version)
    /// 2. Standard paths (/opt/homebrew/bin, /usr/local/bin, etc.)
    /// 3. `which` command as last resort
    ///
    /// - Parameter name: Binary name (e.g., "claude", "gemini", "node")
    /// - Returns: Full path to the binary, or nil if not found
    static func findBinary(_ name: String) -> String? {
        let fm = FileManager.default

        // 1. NVM lookup (for node-based CLIs)
        if let nvmPath = nvmBinPath(for: name) {
            return nvmPath
        }

        // 2. Standard paths
        for dir in standardSearchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. `which` via user's login shell
        if let path = shellWhich(name) {
            return path
        }

        return nil
    }

    /// Run `which` using the user's default shell (login mode for full PATH).
    static func shellWhich(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "which \(command)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }

    // MARK: - Version Parsing

    /// Parse a version string like "v20.19.4" into [20, 19, 4].
    private static func parseVersion(_ versionString: String) -> [Int] {
        let cleaned = versionString.hasPrefix("v") ? String(versionString.dropFirst()) : versionString
        return cleaned.components(separatedBy: ".").compactMap { Int($0) }
    }
}
