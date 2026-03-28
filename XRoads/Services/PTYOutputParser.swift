import Foundation

// MARK: - XRoadsPayload

/// Structured payload emitted by agents via [XROADS:{...}] protocol.
/// Agents emit lines like: [XROADS:{"type":"status","content":"Working on feature X"}]
struct XRoadsPayload: Codable, Sendable {
    let type: String
    let content: String
}

// MARK: - PTYOutputParser

/// Parses PTY stdout lines for structured [XROADS:{...}] messages.
/// Uses Swift Codable JSON decoding — no regex.
struct PTYOutputParser: Sendable {

    private static let prefix = "[XROADS:"
    private static let suffix: Character = "]"

    /// Attempt to extract an XRoadsPayload from a stdout line.
    /// Returns nil if the line does not contain a valid [XROADS:{...}] message.
    func parse(line: String) -> XRoadsPayload? {
        guard let prefixRange = line.range(of: Self.prefix) else {
            return nil
        }

        // Find the closing bracket after the prefix
        let afterPrefix = line[prefixRange.upperBound...]
        guard let closingIndex = afterPrefix.lastIndex(of: Self.suffix) else {
            return nil
        }

        let jsonString = String(afterPrefix[afterPrefix.startIndex..<closingIndex])

        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(XRoadsPayload.self, from: data)
    }

    /// Scan a chunk of stdout text (may contain multiple lines) for all payloads.
    func parseAll(text: String) -> [XRoadsPayload] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parse(line: String($0)) }
    }
}
