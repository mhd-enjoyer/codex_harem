import XCTest
import SQLite3
@testable import PetCore

final class OpenCodeActivityTests: XCTestCase {
    private let now = Date()

    func testUnfinishedAssistantTurnIsActive() {
        let text = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(-2), latestPartType: "text", latestMessageRole: "assistant")
        XCTAssertEqual(OpenCodeReducer.turn(text, now: now), .thinking)
        let tool = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(-2), latestPartType: "tool", latestMessageRole: "assistant")
        XCTAssertEqual(OpenCodeReducer.turn(tool, now: now), .working)
        let unanswered = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(-2), latestMessageRole: "user")
        XCTAssertEqual(OpenCodeReducer.turn(unanswered, now: now), .thinking)
    }

    func testCompletedAssistantTurnIsIgnored() {
        for marker in [true, false] {
            let completed = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(-2), latestPartType: "text", latestMessageRole: "assistant", turnCompleted: marker)
            XCTAssertEqual(OpenCodeReducer.turn(completed, now: now), marker ? nil : .thinking, "turnCompleted=\(marker)")
        }
        // A user message never counts as completed, even with a marker-shaped payload.
        let user = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(-2), latestMessageRole: "user", turnCompleted: true)
        XCTAssertEqual(OpenCodeReducer.turn(user, now: now), .thinking)
    }

    func testStaleTurnDecaysToNoSignal() {
        let stale = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(-OpenCodeReducer.staleInterval - 1), latestPartType: "tool", latestMessageRole: "assistant")
        XCTAssertNil(OpenCodeReducer.turn(stale, now: now))
        let future = OpenCodeReducer.TurnEvidence(updatedAt: now.addingTimeInterval(60), latestPartType: "text", latestMessageRole: "assistant")
        XCTAssertEqual(OpenCodeReducer.turn(future, now: now), .thinking)
    }

    func testActivityPollReadsSharedStorage() throws {
        let database = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("harem-oc-\(UUID().uuidString).db")
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK else { return XCTFail("cannot create test database") }
        defer { sqlite3_close_v2(db); try? FileManager.default.removeItem(at: database) }
        for sql in [
            "CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)",
            "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)",
        ] {
            var create: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &create, nil) == SQLITE_OK, sqlite3_step(create) == SQLITE_DONE else {
                return XCTFail("cannot create table: \(sql)")
            }
            sqlite3_finalize(create)
        }
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        func json(_ pairs: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: pairs)
            return String(data: data, encoding: .utf8)!
        }
        // Busy: assistant turn streaming a tool part one second ago, no completion marker.
        try insert(db, into: "message", values: ["m1", "ses_busy", String(ms - 60_000), String(ms - 1_000), json(["role": "assistant", "time": ["created": ms - 60_000]])])
        try insert(db, into: "part", values: ["p1", "m1", "ses_busy", String(ms - 1_000), String(ms - 1_000), json(["type": "tool", "state": ["status": "running"]])])
        // Finished: completion marker present, so no live status should surface.
        try insert(db, into: "message", values: ["m2", "ses_done", String(ms - 300_000), String(ms - 2_000), json(["role": "assistant", "finish": "tool-calls", "time": ["created": ms - 300_000, "completed": ms - 2_500]])])
        try insert(db, into: "part", values: ["p2", "m2", "ses_done", String(ms - 2_500), String(ms - 2_500), json(["type": "text"])])
        // Stale: active-shaped evidence outside the decay window.
        try insert(db, into: "message", values: ["m3", "ses_dead", String(ms - 4_000_000), String(ms - 4_000_000), json(["role": "assistant", "time": ["created": ms - 4_000_000]])])
        try insert(db, into: "part", values: ["p3", "m3", "ses_dead", String(ms - 4_000_000), String(ms - 4_000_000), json(["type": "tool"])])
        let result = OpenCodeActivity(database: database).poll(now: Date())
        XCTAssertEqual(result["ses_busy"], .working)
        XCTAssertNil(result["ses_done"])
        XCTAssertNil(result["ses_dead"])
        XCTAssertNil(result["ses_missing"])
    }

    private func insert(_ db: OpaquePointer?, into table: String, values: [String]) throws {
        var statement: OpaquePointer?
        let sql = table == "part" ? "INSERT INTO part VALUES (?,?,?,?,?,?)" : "INSERT INTO message VALUES (?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return XCTFail("prepare \(sql)") }
        defer { sqlite3_finalize(statement) }
        let integerIndexes: Set<Int> = table == "part" ? [3, 4] : [2, 3]
        for (index, value) in values.enumerated() {
            if integerIndexes.contains(index) {
                sqlite3_bind_int64(statement, Int32(index + 1), Int64(value) ?? 0)
            } else {
                sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { return XCTFail("insert into \(table)") }
    }
}
