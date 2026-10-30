import Foundation
import SQLite3

/// Reads opencode's shared SQLite storage (`opencode.db`) read-only. The spawned
/// server's `/session/status` and `/event` stream only cover sessions owned by that
/// server process; sessions run in the TUI or another server are visible in storage.
/// The busy signal is structural: a turn is in flight while the newest message has
/// no completion marker, or a recent user prompt has no assistant reply yet.
/// Permission requests are not persisted, so waiting cannot be recovered here.
public final class OpenCodeActivity {
    private let database: URL
    public init(database: URL) { self.database = database }

    /// Session IDs with a live turn, mapped to the status storage implies.
    public func poll(now: Date = Date()) -> [String: PetStatus] {
        guard let db = open() else { return [:] }
        defer { sqlite3_close_v2(db) }
        let cutoff = Int64((now.addingTimeInterval(-OpenCodeReducer.staleInterval).timeIntervalSince1970) * 1000)
        let sessions = Self.rows(db, "SELECT session_id, MAX(time_updated) FROM part WHERE time_updated > ? GROUP BY session_id", [.integer(cutoff)])
            + Self.rows(db, "SELECT session_id, MAX(time_updated) FROM message WHERE time_updated > ? GROUP BY session_id", [.integer(cutoff)])
        var activity: [String: Int64] = [:]
        for row in sessions where row.count >= 2 {
            activity[row[0]] = max(activity[row[0]] ?? 0, Int64(row[1]) ?? 0)
        }
        var result: [String: PetStatus] = [:]
        for (session, stamp) in activity.sorted(by: { $0.value > $1.value }).prefix(64) {
            let partType = Self.rows(db, "SELECT data FROM part WHERE session_id = ? ORDER BY time_updated DESC LIMIT 1", [.text(session)]).first?
                .first.flatMap(Self.field)
                .flatMap { $0["type"] as? String }
            let message = Self.rows(db, "SELECT data FROM message WHERE session_id = ? ORDER BY time_created DESC LIMIT 1", [.text(session)]).first?
                .first.flatMap(Self.field)
            let evidence = OpenCodeReducer.TurnEvidence(
                updatedAt: Date(timeIntervalSince1970: Double(stamp) / 1000),
                latestPartType: partType,
                latestMessageRole: message?["role"] as? String,
                turnCompleted: (message?["time"] as? [String: Any])?["completed"] as? Double != nil || message?["finish"] != nil)
            if let status = OpenCodeReducer.turn(evidence, now: now) { result[session] = status }
        }
        return result
    }

    private func open() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return nil
        }
        return db
    }

    private enum Parameter { case integer(Int64), text(String) }

    private static func rows(_ db: OpaquePointer?, _ sql: String, _ parameters: [Parameter] = []) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, parameter) in parameters.enumerated() {
            switch parameter {
            case .integer(let value): sqlite3_bind_int64(statement, Int32(index + 1), value)
            case .text(let value): sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient)
            }
        }
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columns = Int(sqlite3_column_count(statement))
            var row: [String] = []
            row.reserveCapacity(columns)
            for column in 0..<columns {
                guard let text = sqlite3_column_text(statement, Int32(column)) else { return [] }
                row.append(String(cString: text))
            }
            rows.append(row)
        }
        return rows
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func field(_ json: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }
}
