import Foundation

/// Reduces Claude Code transcript records without executing tools or reading message contents.
public enum ClaudeReducer {
    /// Maps a transcript JSONL record to a pet status. Returns nil for records without runtime signal
    /// (metadata, attachments, snapshots, system records).
    public static func transcript(_ message: [String: Any]) -> PetStatus? {
        let type = message["type"] as? String
        if type == "system", message["subtype"] as? String == "turn_duration" { return .completed }
        guard let content = (message["message"] as? [String: Any])?["content"] else { return nil }
        if type == "assistant" {
            if let blocks = content as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "tool_use" }) { return .working }
            return .thinking
        }
        if type == "user" {
            if let blocks = content as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return .thinking }
            return content is String ? .thinking : nil
        }
        return nil
    }
    public static func title(_ message: [String: Any]) -> String? {
        guard message["type"] as? String == "ai-title" else { return nil }
        return message["aiTitle"] as? String
    }
    public static func cwd(_ message: [String: Any]) -> String? {
        message["cwd"] as? String
    }
}

/// Incremental tail of Claude Code session transcripts under `<home>/projects`.
/// Threads are namespaced as `claude:<session-uuid>` so bindings never collide with Codex threads.
public final class ClaudeMonitor {
    /// Unfinished turns older than this are decayed to idle: transcripts end without a
    /// terminal marker when a session is killed, so old work evidence must not persist.
    public static let staleInterval: TimeInterval = 900
    private let root: URL
    private var tails: [URL: JSONLTail] = [:]
    public private(set) var threads: [String: ThreadState] = [:]
    public init(home: URL) { root = home.appendingPathComponent("projects") }
    public func poll(now: Date = Date()) -> [ThreadState] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return Array(threads.values) }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
               let date = values.contentModificationDate { files.append((url, date)) }
        }
        let recent = files.sorted { $0.1 > $1.1 }.prefix(64)
        let retained = Set(recent.map(\.0))
        tails = tails.filter { retained.contains($0.key) }
        var ids = Set<String>()
        for (url, modified) in recent {
            // Transcript filenames are the session UUID; no user text is needed.
            let stem = url.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: stem) != nil else { continue }
            let id = "claude:" + stem
            ids.insert(id)
            var state = threads[id] ?? ThreadState(id: id, name: "Claude · \(stem.prefix(8))", status: .idle, updatedAt: modified, harness: .claude)
            var tail = tails[url] ?? JSONLTail()
            if let events = try? tail.read(url) {
                for event in events {
                    if let title = ClaudeReducer.title(event), !title.isEmpty { state.name = title }
                    if let cwd = ClaudeReducer.cwd(event), state.name.hasPrefix("Claude · ") {
                        state.name = URL(fileURLWithPath: cwd).lastPathComponent + " · " + stem.prefix(8)
                    }
                    if let status = ClaudeReducer.transcript(event) {
                        state.status = status
                        if let stamp = event["timestamp"] as? String, let date = Self.date(stamp) { state.updatedAt = date }
                        else { state.updatedAt = modified }
                    }
                }
            }
            tails[url] = tail
            if state.status == .working || state.status == .thinking,
               now.timeIntervalSince(state.updatedAt) > ClaudeMonitor.staleInterval { state.status = .idle }
            threads[id] = state
        }
        threads = threads.filter { ids.contains($0.key) }
        return Array(threads.values)
    }
    private static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
