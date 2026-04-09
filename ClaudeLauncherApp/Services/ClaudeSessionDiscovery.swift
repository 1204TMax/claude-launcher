import Foundation

struct DiscoveredClaudeSession: Identifiable, Equatable {
    let id: String
    let pid: Int32
    let sessionID: String?
    let cwd: String
    let startedAt: Date?
    let name: String?

    var normalizedName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class ClaudeSessionDiscovery {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func discoverLiveSessions() -> [DiscoveredClaudeSession] {
        let pids = liveClaudePIDs()
        return pids.compactMap { pid in
            guard let metadata = loadMetadata(for: pid) else { return nil }
            return DiscoveredClaudeSession(
                id: metadata.sessionID ?? "pid-\(pid)",
                pid: pid,
                sessionID: metadata.sessionID,
                cwd: metadata.cwd,
                startedAt: metadata.startedAt,
                name: metadata.name
            )
        }
    }

    private func liveClaudePIDs() -> [Int32] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return output
                .split(separator: "\n")
                .compactMap { line in
                    let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                    guard parts.count >= 2, let pid = Int32(parts[0]) else { return nil }
                    let command = parts[1]
                    return command.hasSuffix("/claude") || command == "claude" ? pid : nil
                }
        } catch {
            return []
        }
    }

    private func loadMetadata(for pid: Int32) -> ClaudeSessionMetadata? {
        let path = NSHomeDirectory() + "/.claude/sessions/\(pid).json"
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder.claudeSessionDecoder.decode(ClaudeSessionMetadata.self, from: data)
    }
}

private struct ClaudeSessionMetadata: Decodable {
    let pid: Int32
    let sessionID: String?
    let cwd: String
    let startedAt: Date?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case pid
        case sessionID = "sessionId"
        case cwd
        case startedAt
        case name
    }
}

private extension JSONDecoder {
    static var claudeSessionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let milliseconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }
            if let isoString = try? container.decode(String.self), let date = ISO8601DateFormatter().date(from: isoString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format")
        }
        return decoder
    }
}
