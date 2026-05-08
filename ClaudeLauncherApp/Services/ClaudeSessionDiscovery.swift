import Foundation

private struct LiveProcessSession: Identifiable, Equatable {
    let id: String
    let cliKind: CLIKind
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

private struct ProcessInfo {
    let parentPID: Int32?
    let tty: String?
}

private struct TranscriptSummary {
    var name: String?
    var cwd: String?
    var startedAt: Date?
    var lastActivityAt: Date?
    var preview: String = ""
}

private struct SessionFileRecord {
    let cliKind: CLIKind
    let sessionID: String
    let url: URL
    let startedAt: Date?
    let lastActivityAt: Date?
    let name: String?
    let cwd: String?
}

final class ClaudeSessionDiscovery {
    private let fileManager: FileManager
    private let isoFormatter = ISO8601DateFormatter()
    private var cachedSessionFiles: [String: SessionFileRecord] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func discoverAllSessions() -> [DiscoveredSession] {
        let liveSessions = discoverLiveSessions()
        var liveBySessionID: [String: LiveProcessSession] = [:]
        for session in liveSessions {
            if let sessionID = session.sessionID {
                liveBySessionID[sessionID] = session
            }
        }

        var merged: [String: DiscoveredSession] = [:]

        for record in sessionFiles() {
            let liveSession = liveBySessionID[record.sessionID]
            let resolvedDate = record.lastActivityAt
                ?? liveSession?.startedAt
                ?? record.startedAt
                ?? modificationDate(for: record.url)
                ?? Date.distantPast

            merged[record.sessionID] = DiscoveredSession(
                id: record.sessionID,
                cliKind: record.cliKind,
                sessionID: record.sessionID,
                name: liveSession?.normalizedName ?? record.name,
                cwd: liveSession?.cwd ?? record.cwd ?? NSHomeDirectory(),
                startedAt: liveSession?.startedAt ?? record.startedAt,
                lastActivityAt: resolvedDate,
                preview: record.previewText,
                isLive: liveSession != nil,
                pid: liveSession?.pid,
                tty: liveSession?.tty,
                transcriptAvailabilityNote: record.cliKind.capabilities.transcriptAvailabilityNote
            )
        }

        for liveSession in liveSessions where merged[liveSession.sessionID ?? ""] == nil {
            let sessionID = liveSession.sessionID ?? "pid-\(liveSession.pid)"
            merged[sessionID] = DiscoveredSession(
                id: sessionID,
                cliKind: liveSession.cliKind,
                sessionID: sessionID,
                name: liveSession.normalizedName,
                cwd: liveSession.cwd,
                startedAt: liveSession.startedAt,
                lastActivityAt: liveSession.startedAt ?? Date.distantPast,
                preview: "",
                isLive: true,
                pid: liveSession.pid,
                tty: liveSession.tty,
                transcriptAvailabilityNote: liveSession.cliKind.capabilities.transcriptAvailabilityNote
            )
        }

        return merged.values.sorted { lhs, rhs in
            lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    func loadTranscriptMessages(sessionID: String, limit: Int = 80) -> [TranscriptMessage] {
        guard let record = cachedSessionFiles[sessionID] ?? sessionFiles().first(where: { $0.sessionID == sessionID }) else {
            return []
        }

        switch record.cliKind {
        case .claude:
            return loadClaudeTranscriptMessages(from: record.url, sessionID: sessionID, limit: limit)
        case .gemini:
            return loadGeminiTranscriptMessages(from: record.url, sessionID: sessionID, limit: limit)
        case .codex:
            return loadCodexTranscriptMessages(sessionID: sessionID, limit: limit)
        }
    }

    private func discoverLiveSessions() -> [LiveProcessSession] {
        let processMap = liveProcessInfo()
        return processMap.compactMap { pid, process in
            switch process.cliKind {
            case .claude:
                guard let metadata = loadClaudeMetadata(for: pid) else { return nil }
                return LiveProcessSession(
                    id: metadata.sessionID ?? "pid-\(pid)",
                    cliKind: .claude,
                    pid: pid,
                    parentPID: process.info.parentPID,
                    tty: process.info.tty,
                    sessionID: metadata.sessionID,
                    cwd: metadata.cwd,
                    startedAt: metadata.startedAt,
                    name: metadata.name
                )
            case .gemini:
                return LiveProcessSession(
                    id: "pid-\(pid)",
                    cliKind: .gemini,
                    pid: pid,
                    parentPID: process.info.parentPID,
                    tty: process.info.tty,
                    sessionID: discoverGeminiSessionID(for: process.info.tty),
                    cwd: currentWorkingDirectory(for: pid) ?? NSHomeDirectory(),
                    startedAt: nil,
                    name: nil
                )
            case .codex:
                return LiveProcessSession(
                    id: "pid-\(pid)",
                    cliKind: .codex,
                    pid: pid,
                    parentPID: process.info.parentPID,
                    tty: process.info.tty,
                    sessionID: discoverCodexSessionID(for: process.info.tty),
                    cwd: currentWorkingDirectory(for: pid) ?? NSHomeDirectory(),
                    startedAt: nil,
                    name: nil
                )
            }
        }
    }

    private func sessionFiles() -> [SessionFileRecord] {
        var records: [SessionFileRecord] = []
        var index: [String: SessionFileRecord] = [:]

        for record in claudeSessionFiles() {
            records.append(record)
            index[record.sessionID] = record
        }
        for record in geminiSessionFiles() {
            records.append(record)
            index[record.sessionID] = record
        }
        for record in codexSessionFiles() {
            records.append(record)
            index[record.sessionID] = record
        }

        cachedSessionFiles = index
        return records
    }

    private func claudeSessionFiles() -> [SessionFileRecord] {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var records: [SessionFileRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  !url.path.contains("/subagents/") else {
                continue
            }
            guard let summary = summarizeClaudeTranscriptLite(at: url) else { continue }
            let sessionID = url.deletingPathExtension().lastPathComponent
            records.append(SessionFileRecord(
                cliKind: .claude,
                sessionID: sessionID,
                url: url,
                startedAt: summary.startedAt,
                lastActivityAt: summary.lastActivityAt,
                name: summary.name,
                cwd: summary.cwd
            ))
        }
        return records
    }

    private func geminiSessionFiles() -> [SessionFileRecord] {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/tmp", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var records: [SessionFileRecord] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("session-"),
                  ["json", "jsonl"].contains(url.pathExtension) else {
                continue
            }
            guard let summary = summarizeGeminiTranscriptLite(at: url), let sessionID = summary.sessionID else { continue }
            records.append(SessionFileRecord(
                cliKind: .gemini,
                sessionID: sessionID,
                url: url,
                startedAt: summary.startedAt,
                lastActivityAt: summary.lastActivityAt,
                name: summary.name,
                cwd: summary.cwd
            ))
        }
        return records
    }

    private func codexSessionFiles() -> [SessionFileRecord] {
        let indexURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/session_index.jsonl")
        guard fileManager.fileExists(atPath: indexURL.path),
              let content = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return []
        }

        var dedup: [String: SessionFileRecord] = [:]
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = object["id"] as? String else {
                continue
            }
            let name = (object["thread_name"] as? String)?.trimmedNonEmpty
            let updatedAt = parseTimestamp(object["updated_at"])
            let record = SessionFileRecord(
                cliKind: .codex,
                sessionID: sessionID,
                url: indexURL,
                startedAt: updatedAt,
                lastActivityAt: updatedAt,
                name: name,
                cwd: nil
            )
            dedup[sessionID] = record
        }
        return Array(dedup.values)
    }

    private func summarizeClaudeTranscriptLite(at url: URL) -> TranscriptSummary? {
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

    private func summarizeGeminiTranscriptLite(at url: URL) -> (sessionID: String?, startedAt: Date?, lastActivityAt: Date?, name: String?, cwd: String?)? {
        if url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let sessionID = object["sessionId"] as? String
            let startedAt = parseTimestamp(object["startTime"])
            let lastActivityAt = parseTimestamp(object["lastUpdated"])
            let messages = object["messages"] as? [[String: Any]] ?? []
            let name = geminiConversationTitle(fromMessages: messages)
            return (sessionID, startedAt, lastActivityAt, name, nil)
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var sessionID: String?
        var startedAt: Date?
        var lastActivityAt: Date?
        var messages: [[String: Any]] = []

        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if sessionID == nil, let value = object["sessionId"] as? String {
                sessionID = value
                startedAt = parseTimestamp(object["startTime"])
                lastActivityAt = parseTimestamp(object["lastUpdated"])
                continue
            }
            if let set = object["$set"] as? [String: Any], let updated = parseTimestamp(set["lastUpdated"]) {
                lastActivityAt = updated
                continue
            }
            messages.append(object)
            if let timestamp = parseTimestamp(object["timestamp"]) {
                lastActivityAt = timestamp
            }
        }

        let name = geminiConversationTitle(fromMessages: messages)
        return (sessionID, startedAt, lastActivityAt, name, nil)
    }

    private func loadClaudeTranscriptMessages(from url: URL, sessionID: String, limit: Int) -> [TranscriptMessage] {
        guard let content = readSuffixString(from: url, maxBytes: 512 * 1024) else {
            return []
        }

        var messages: [TranscriptMessage] = []
        for (index, line) in content.split(separator: "\n").enumerated() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  (type == "user" || type == "assistant") else {
                continue
            }

            let text = extractClaudeDisplayText(from: object)
            guard !text.isEmpty else { continue }

            messages.append(
                TranscriptMessage(
                    id: (object["uuid"] as? String) ?? "\(sessionID)-\(index)",
                    role: type == "user" ? .user : .assistant,
                    text: text,
                    timestamp: parseTimestamp(object["timestamp"])
                )
            )
        }
        return Array(messages.suffix(limit))
    }

    private func loadGeminiTranscriptMessages(from url: URL, sessionID: String, limit: Int) -> [TranscriptMessage] {
        if url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = object["messages"] as? [[String: Any]] else {
                return []
            }
            return Array(parseGeminiMessages(messages, sessionID: sessionID).suffix(limit))
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var objects: [[String: Any]] = []
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["id"] != nil else {
                continue
            }
            objects.append(object)
        }
        return Array(parseGeminiMessages(objects, sessionID: sessionID).suffix(limit))
    }

    private func parseGeminiMessages(_ messages: [[String: Any]], sessionID: String) -> [TranscriptMessage] {
        var result: [TranscriptMessage] = []
        for (index, object) in messages.enumerated() {
            guard let type = object["type"] as? String else { continue }
            let timestamp = parseTimestamp(object["timestamp"])
            switch type {
            case "user":
                let text = geminiText(from: object["content"])
                guard !text.isEmpty else { continue }
                result.append(TranscriptMessage(
                    id: (object["id"] as? String) ?? "\(sessionID)-user-\(index)",
                    role: .user,
                    text: text,
                    timestamp: timestamp
                ))
            case "gemini", "assistant":
                let text = geminiText(from: object["content"])
                if !text.isEmpty {
                    result.append(TranscriptMessage(
                        id: (object["id"] as? String) ?? "\(sessionID)-assistant-\(index)",
                        role: .assistant,
                        text: text,
                        timestamp: timestamp
                    ))
                }
            case "error", "info":
                let text = (object["content"] as? String)?.trimmedNonEmpty ?? ""
                guard !text.isEmpty else { continue }
                result.append(TranscriptMessage(
                    id: (object["id"] as? String) ?? "\(sessionID)-system-\(index)",
                    role: .system,
                    text: text,
                    timestamp: timestamp
                ))
            default:
                continue
            }
        }
        return result
    }

    private func loadCodexTranscriptMessages(sessionID: String, limit: Int) -> [TranscriptMessage] {
        let historyURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/history.jsonl")
        guard fileManager.fileExists(atPath: historyURL.path),
              let content = readSuffixString(from: historyURL, maxBytes: 1024 * 1024) else {
            return []
        }

        var messages: [TranscriptMessage] = []
        for (index, line) in content.split(separator: "\n").enumerated() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let recordSessionID = object["session_id"] as? String,
                  recordSessionID == sessionID,
                  let text = object["text"] as? String else {
                continue
            }
            messages.append(TranscriptMessage(
                id: "\(sessionID)-codex-\(index)",
                role: .user,
                text: text,
                timestamp: parseTimestamp(object["ts"])
            ))
        }
        return Array(messages.suffix(limit))
    }

    private func extractClaudeDisplayText(from object: [String: Any]) -> String {
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

    private func geminiText(from content: Any?) -> String {
        if let string = content as? String {
            return normalizeDisplayText(string)
        }
        if let items = content as? [[String: Any]] {
            let text = items.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
            return normalizeDisplayText(text)
        }
        return ""
    }

    private func geminiConversationTitle(fromMessages messages: [[String: Any]]) -> String? {
        for object in messages {
            if let type = object["type"] as? String, type == "user" {
                let text = geminiText(from: object["content"])
                if !text.isEmpty {
                    return String(text.prefix(80)).trimmedNonEmpty
                }
            }
        }
        return nil
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
        if let seconds = rawValue as? Double {
            if seconds > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = rawValue as? Int64 {
            if seconds > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: Double(seconds) / 1000)
            }
            return Date(timeIntervalSince1970: Double(seconds))
        }
        if let seconds = rawValue as? Int {
            if seconds > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: Double(seconds) / 1000)
            }
            return Date(timeIntervalSince1970: Double(seconds))
        }
        return nil
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
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

    private func liveProcessInfo() -> [Int32: (cliKind: CLIKind, info: ProcessInfo)] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,tty=,comm="]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            var result: [Int32: (cliKind: CLIKind, info: ProcessInfo)] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 4, let pid = Int32(parts[0]) else { continue }
                let ppid = Int32(parts[1])
                let tty = parts[2] == "??" ? nil : parts[2]
                let command = parts[3]
                if command.hasSuffix("/claude") || command == "claude" {
                    result[pid] = (.claude, ProcessInfo(parentPID: ppid, tty: tty))
                } else if command.hasSuffix("/gemini") || command == "gemini" {
                    result[pid] = (.gemini, ProcessInfo(parentPID: ppid, tty: tty))
                } else if command.hasSuffix("/codex") || command == "codex" {
                    result[pid] = (.codex, ProcessInfo(parentPID: ppid, tty: tty))
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    private func loadClaudeMetadata(for pid: Int32) -> ClaudeSessionMetadata? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/sessions", isDirectory: true)
            .appendingPathComponent("\(pid).json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.claudeSessionDecoder.decode(ClaudeSessionMetadata.self, from: data)
    }

    private func currentWorkingDirectory(for pid: Int32) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/pwdx")
        process.arguments = [String(pid)]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let parts = output.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func discoverGeminiSessionID(for tty: String?) -> String? {
        guard let tty else { return nil }
        let suffix = tty.replacingOccurrences(of: "/dev/", with: "")
        let live = discoverMostRecentLiveSessionID(in: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/tmp", isDirectory: true), matchingTTY: suffix)
        if let live { return live }
        return nil
    }

    private func discoverCodexSessionID(for tty: String?) -> String? {
        guard tty != nil else { return nil }
        return nil
    }

    private func discoverMostRecentLiveSessionID(in root: URL, matchingTTY: String) -> String? {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var candidates: [(date: Date, sessionID: String)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("session-"), url.pathExtension == "jsonl" else { continue }
            guard let content = readSuffixString(from: url, maxBytes: 16 * 1024), content.contains(matchingTTY) else { continue }
            let modification = modificationDate(for: url) ?? .distantPast
            if let summary = summarizeGeminiTranscriptLite(at: url), let sessionID = summary.sessionID {
                candidates.append((modification, sessionID))
            }
        }
        return candidates.sorted { $0.date > $1.date }.first?.sessionID
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

private extension SessionFileRecord {
    var previewText: String { "" }
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
