import Foundation
import Darwin

/// Incremental, bounded JSONL reader. Partial writes are retained until a newline arrives.
public struct JSONLTail {
    public private(set) var offset: UInt64 = 0
    private var remainder = Data()
    private var identity: String?
    public init() {}
    public mutating func read(_ url: URL, initialLimit: UInt64 = 524_288) throws -> [[String: Any]] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var metadata = stat()
        if fstat(file.fileDescriptor, &metadata) == 0 {
            let current = "\(metadata.st_dev):\(metadata.st_ino)"
            if let identity, identity != current { offset = 0; remainder.removeAll() }
            identity = current
        }
        let length = try file.seekToEnd()
        if length < offset { offset = 0; remainder.removeAll() }
        var skipFirst = false
        if offset == 0 && length > initialLimit { offset = length - initialLimit; skipFirst = true }
        try file.seek(toOffset: offset)
        let data = try file.read(upToCount: 2_097_152) ?? Data()
        offset += UInt64(data.count)
        remainder.append(data)
        var result: [[String: Any]] = []
        while let end = remainder.firstIndex(of: 10) {
            let line = remainder[..<end]
            if !skipFirst, let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { result.append(value) }
            skipFirst = false
            remainder.removeSubrange(...end)
        }
        // A corrupt or huge record must not grow memory indefinitely.
        if remainder.count > 4_194_304 { remainder.removeAll() }
        return result
    }
}

public final class RolloutMonitor {
    private let root: URL
    private var tails: [URL: JSONLTail] = [:]
    public private(set) var threads: [String: ThreadState] = [:]
    public init(home: URL) { root = home.appendingPathComponent("sessions") }
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
            // Rollout filenames end in the thread UUID; no user text is needed.
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.count >= 36 else { continue }
            let id = String(stem.suffix(36))
            guard UUID(uuidString: id) != nil else { continue }
            ids.insert(id)
            var state = threads[id] ?? ThreadState(id: id, name: "Thread \(id.prefix(8))", status: .offline, updatedAt: modified)
            var tail = tails[url] ?? JSONLTail()
            if let events = try? tail.read(url) {
                for event in events {
                    if event["type"] as? String == "session_meta", let p = event["payload"] as? [String: Any], let cwd = p["cwd"] as? String {
                        state.name = URL(fileURLWithPath: cwd).lastPathComponent + " · " + id.prefix(8)
                    }
                    if let status = StatusReducer.rollout(event) {
                        state.status = status
                        if let stamp = event["timestamp"] as? String, let date = Self.date(stamp) { state.updatedAt = date }
                        else { state.updatedAt = modified }
                    }
                }
            }
            tails[url] = tail
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
