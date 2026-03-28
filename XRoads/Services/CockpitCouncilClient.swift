import Foundation
import os

// MARK: - CockpitCouncilError

enum CockpitCouncilError: LocalizedError, Sendable {
    case pythonNotFound
    case councilNotAvailable(String)
    case invalidOutput(String)
    case executionFailed(String)
    case noAssignments

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python3 not found in system PATH"
        case .councilNotAvailable(let reason):
            return "cockpit-council unavailable: \(reason)"
        case .invalidOutput(let detail):
            return "Invalid Chairman output: \(detail)"
        case .executionFailed(let reason):
            return "cockpit-council execution failed: \(reason)"
        case .noAssignments:
            return "Chairman returned zero slot assignments"
        }
    }
}

// MARK: - CockpitCouncilClientProtocol

/// Protocol for Chairman deliberation — enables test injection.
protocol CockpitCouncilClientProtocol: Sendable {
    func deliberate(input: ChairmanInput) async throws -> ChairmanOutput
}

// MARK: - CockpitCouncilClient

/// Wraps cockpit-council Python library via subprocess.
/// Sends ChairmanInput as JSON stdin, receives ChairmanOutput as JSON stdout.
actor CockpitCouncilClient: CockpitCouncilClientProtocol {

    private let logger = Logger(subsystem: "com.xroads", category: "CouncilClient")

    /// Path to python3 binary (resolved at init)
    private let pythonPath: String

    init(pythonPath: String? = nil) throws {
        if let path = pythonPath {
            self.pythonPath = path
        } else {
            self.pythonPath = try Self.findPython()
        }
    }

    /// Sends ChairmanInput to cockpit-council and returns the Chairman's output.
    func deliberate(input: ChairmanInput) async throws -> ChairmanOutput {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)

        logger.info("Sending ChairmanInput to cockpit-council (\(inputData.count) bytes)")

        let outputData = try await runCouncil(inputJSON: inputData)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let output = try decoder.decode(ChairmanOutput.self, from: outputData)

            guard !output.assignments.isEmpty else {
                throw CockpitCouncilError.noAssignments
            }

            logger.info("Chairman deliberated: \(output.assignments.count) slot assignments")
            return output
        } catch let error as CockpitCouncilError {
            throw error
        } catch {
            throw CockpitCouncilError.invalidOutput(error.localizedDescription)
        }
    }

    // MARK: - Private

    /// Executes cockpit-council via Python subprocess.
    /// Passes ChairmanInput JSON on stdin, reads ChairmanOutput JSON from stdout.
    private func runCouncil(inputJSON: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-m", "cockpit_council", "--chairman"]

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let errMsg = String(data: stderr, encoding: .utf8) ?? "unknown error"
                    continuation.resume(throwing: CockpitCouncilError.executionFailed(errMsg))
                }
            }

            do {
                try process.run()
                stdinPipe.fileHandleForWriting.write(inputJSON)
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: CockpitCouncilError.councilNotAvailable(error.localizedDescription))
            }
        }
    }

    /// Finds python3 in common locations
    private static func findPython() throws -> String {
        let candidates = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3"
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        throw CockpitCouncilError.pythonNotFound
    }
}

// MARK: - MockCockpitCouncilClient

/// Mock client for testing — returns a predetermined ChairmanOutput.
final class MockCockpitCouncilClient: CockpitCouncilClientProtocol, @unchecked Sendable {
    private let output: ChairmanOutput?
    private let error: Error?

    init(output: ChairmanOutput) {
        self.output = output
        self.error = nil
    }

    init(error: Error) {
        self.output = nil
        self.error = error
    }

    func deliberate(input: ChairmanInput) async throws -> ChairmanOutput {
        if let error {
            throw error
        }
        return output!
    }
}
