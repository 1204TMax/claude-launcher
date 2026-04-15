import Foundation

struct DiscoveredClaudeSession: Identifiable, Equatable {
    let id: String
    let pid: Int32
    let parentPID: Int32?
    let tty: String?
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

struct ClaudeTranscriptSession: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let name: String?
    let cwd: String
    let startedAt: Date?
    let lastActivityAt: Date
    let preview: String
    let isLive: Bool
    let pid: Int32?
}

enum ClaudeTranscriptRole: String, Equatable {
    case user
    case assistant
}

struct ClaudeTranscriptMessage: Identifiable, Equatable {
    let id: String
    let role: ClaudeTranscriptRole
    let text: String
    let timestamp: Date?
}

final class ClaudeSessionDiscovery {
    private let fileManager: FileManager
    private let isoFormatter = ISO8601DateFormatter()
    private var cachedTranscriptURLs: [URL]?
    private var cachedTranscriptURLBySessionID: [String: URL] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func discoverAllSessions() -> [ClaudeTranscriptSession] {
        let liveSessions = discoverLiveSessions()
        var liveBySessionID: [String: DiscoveredClaudeSession] = [:]
        for session in liveSessions {
            if let sessionID = session.sessionID {
                liveBySessionID[sessionID] = session
            }
        }

        return transcriptURLs().compactMap { url -> ClaudeTranscriptSession? in
            let sessionID = url.deletingPathExtension().lastPathComponent
            guard let summary = summarizeTranscriptLite(at: url) else { return nil }
            let liveSession = liveBySessionID[sessionID]
            let resolvedDate = summary.lastActivityAt
                ?? liveSession?.startedAt
                ?? summary.startedAt
                ?? modificationDate(for: url)
                ?? Date.distantPast

            return ClaudeTranscriptSession(
                id: sessionID,
                sessionID: sessionID,
                name: liveSession?.normalizedName ?? summary.name,
                cwd: liveSession?.cwd ?? summary.cwd ?? NSHomeDirectory(),
                startedAt: liveSession?.startedAt ?? summary.startedAt,
                lastActivityAt: resolvedDate,
                preview: "",
                isLive: liveSession != nil,
                pid: liveSession?.pid
            )
        }
        .sorted { lhs, rhs in
            lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    func loadTranscriptMessages(sessionID: String, limit: Int = 80) -> [ClaudeTranscriptMessage] {
        guard let url = transcriptURL(for: sessionID),
              let content = readSuffixString(from: url, maxBytes: 512 * 1024) else {
            return []
        }

        var messages: [ClaudeTranscriptMessage] = []
        for (index, line) in content.split(separator: "\n").enumerated() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  (type == "user" || type == "assistant") else {
                continue
            }

            let text = extractDisplayText(from: object)
            guard !text.isEmpty else { continue }

            messages.append(
                ClaudeTranscriptMessage(
                    id: (object["uuid"] as? String) ?? "\(sessionID)-\(index)",
                    role: type == "user" ? .user : .assistant,
                    text: text,
                    timestamp: parseTimestamp(object["timestamp"])
                )
            )
        }
        return Array(messages.suffix(limit))
    }

    func discoverLiveSessions() -> [DiscoveredClaudeSession] {
        let processMap = liveClaudeProcessInfo()
        return processMap.compactMap { pid, info in
            guard let metadata = loadMetadata(for: pid) else { return nil }
            return DiscoveredClaudeSession(
                id: metadata.sessionID ?? "pid-\(pid)",
                pid: pid,
                parentPID: info.parentPID,
                tty: info.tty,
                sessionID: metadata.sessionID,
                cwd: metadata.cwd,
                startedAt: metadata.startedAt,
                name: metadata.name
            )
        }
    }

    func updateSessionMetadataName(pid: Int32, name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        let url = metadataURL(for: pid)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        object["name"] = trimmedName

        do {
            let updatedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try updatedData.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private struct TranscriptSummary {
        var name: String?
        var cwd: String?
        var startedAt: Date?
        var lastActivityAt: Date?
        var preview: String = ""
    }

    private struct ProcessInfo {
        let parentPID: Int32?
        let tty: String?
    }

    private func transcriptURLs() -> [URL] {
        if let cachedTranscriptURLs {
            return cachedTranscriptURLs
        }

        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var urls: [URL] = []
        var urlBySessionID: [String: URL] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  !url.path.contains("/subagents/") else {
                continue
            }
            urls.append(url)
            urlBySessionID[url.deletingPathExtension().lastPathComponent] = url
        }
        cachedTranscriptURLs = urls
        cachedTranscriptURLBySessionID = urlBySessionID
        return urls
    }

    private func transcriptURL(for sessionID: String) -> URL? {
        if let url = cachedTranscriptURLBySessionID[sessionID] {
            return url
        }
        _ = transcriptURLs()
        return cachedTranscriptURLBySessionID[sessionID]
    }

    private func readPrefixString(from url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: maxBytes)
        guard let data, !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func readSuffixString(from url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let start = max(Int64(fileSize) - Int64(maxBytes), 0)
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        let content = String(decoding: data, as: UTF8.self)
        if start == 0 {
            return content
        }
        guard let newlineIndex = content.firstIndex(of: "\n") else {
            return content
        }
        return String(content[content.index(after: newlineIndex)...])
    }

    private func summarizeTranscriptLite(at url: URL) -> TranscriptSummary? {
        let prefix = readPrefixString(from: url, maxBytes: 16 * 1024) ?? ""
        let suffix = readSuffixString(from: url, maxBytes: 32 * 1024) ?? ""
        guard !prefix.isEmpty || !suffix.isEmpty else { return nil }

        var summary = TranscriptSummary()

        for line in prefix.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                continue
            }

            switch type {
            case "custom-title":
                if summary.name == nil {
                    summary.name = (object["customTitle"] as? String)?.trimmedNonEmpty
                }
            case "user", "assistant":
                if summary.cwd == nil {
                    summary.cwd = (object["cwd"] as? String)?.trimmedNonEmpty
                }
                let timestamp = parseTimestamp(object["timestamp"])
                if summary.startedAt == nil {
                    summary.startedAt = timestamp
                }
            default:
                continue
            }
        }

        for line in suffix.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                continue
            }

            switch type {
            case "custom-title":
                summary.name = (object["customTitle"] as? String)?.trimmedNonEmpty ?? summary.name
            case "user", "assistant":
                if summary.cwd == nil {
                    summary.cwd = (object["cwd"] as? String)?.trimmedNonEmpty
                }
                if let timestamp = parseTimestamp(object["timestamp"]) {
                    summary.lastActivityAt = timestamp
                }
            default:
                continue
            }
        }

        return summary
    }

    private func extractDisplayText(from object: [String: Any]) -> String {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] else {
            return ""
        }

        if let content = content as? String {
            return normalizeDisplayText(content)
        }

        if let items = content as? [[String: Any]] {
            let texts = items.compactMap { item -> String? in
                guard let type = item["type"] as? String else { return nil }
                switch type {
                case "text":
                    return item["text"] as? String
                default:
                    return nil
                }
            }
            return normalizeDisplayText(texts.joined(separator: "\n\n"))
        }

        return ""
    }

    private func normalizeDisplayText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTimestamp(_ rawValue: Any?) -> Date? {
        guard let rawValue else { return nil }
        if let string = rawValue as? String {
            return isoFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }
        if let milliseconds = rawValue as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        if let milliseconds = rawValue as? Int64 {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        if let milliseconds = rawValue as? Int {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        return nil
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func liveClaudeProcessInfo() -> [Int32: ProcessInfo] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,tty=,comm="]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            var result: [Int32: ProcessInfo] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 4, let pid = Int32(parts[0]) else { continue }
                let ppid = Int32(parts[1])
                let tty = parts[2] == "??" ? nil : parts[2]
                let command = parts[3]
                if command.hasSuffix("/claude") || command == "claude" {
                    result[pid] = ProcessInfo(parentPID: ppid, tty: tty)
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    private func loadMetadata(for pid: Int32) -> ClaudeSessionMetadata? {
        let url = metadataURL(for: pid)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.claudeSessionDecoder.decode(ClaudeSessionMetadata.self, from: data)
    }

    private func metadataURL(for pid: Int32) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/sessions", isDirectory: true)
            .appendingPathComponent("\(pid).json")
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
