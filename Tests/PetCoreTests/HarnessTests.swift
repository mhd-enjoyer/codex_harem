import XCTest
@testable import PetCore

final class HarnessTests: XCTestCase {
    func testHarnessDisplayNames() {
        XCTAssertEqual(Harness.allCases.count, 4)
        XCTAssertEqual(Harness.claude.displayName, "Claude Code")
        XCTAssertEqual(Harness.all.displayName, "All harnesses")
    }

    func testClaudeReducerMapsTranscriptRecords() {
        let assistant: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "name": "Bash"]]]]
        XCTAssertEqual(ClaudeReducer.transcript(assistant), .working)
        let text: [String: Any] = ["type": "assistant", "message": ["content": [["type": "text"], ["type": "thinking"]]]]
        XCTAssertEqual(ClaudeReducer.transcript(text), .thinking)
        let toolResult: [String: Any] = ["type": "user", "message": ["content": [["type": "tool_result"]]]]
        XCTAssertEqual(ClaudeReducer.transcript(toolResult), .thinking)
        let prompt: [String: Any] = ["type": "user", "message": ["content": "Fix the tests"]]
        XCTAssertEqual(ClaudeReducer.transcript(prompt), .thinking)
        let sidechain: [String: Any] = ["type": "assistant", "isSidechain": true, "message": ["content": [["type": "tool_use"]]]]
        XCTAssertEqual(ClaudeReducer.transcript(sidechain), .working)
        let meta: [String: Any] = ["type": "ai-title", "aiTitle": "Title"]
        XCTAssertNil(ClaudeReducer.transcript(meta))
        let snapshot: [String: Any] = ["type": "file-history-snapshot"]
        XCTAssertNil(ClaudeReducer.transcript(snapshot))
        let turnEnd: [String: Any] = ["type": "system", "subtype": "turn_duration", "durationMs": 31788]
        XCTAssertEqual(ClaudeReducer.transcript(turnEnd), .completed)
    }

    func testClaudeReducerTitles() {
        XCTAssertEqual(ClaudeReducer.title(["type": "ai-title", "aiTitle": "My work"]), "My work")
        XCTAssertNil(ClaudeReducer.title(["type": "assistant"]))
    }

    func testClaudeMonitorTailsTranscripts() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("harem-claude-\(UUID().uuidString)")
        let project = home.appendingPathComponent("projects/-Users-demo-repo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let uuid = "12345678-1234-1234-1234-123456789012"
        let file = project.appendingPathComponent("\(uuid).jsonl")
        let stamp = "2026-10-30T00:00:00.000Z"
        let first = #"{"type":"assistant","cwd":"/Users/demo/repo","sessionId":"\#(uuid)","timestamp":"\#(stamp)","message":{"content":[{"type":"text","text":"Thinking about it"}]}}"#
        try Data((first + "\n").utf8).write(to: file)
        let monitor = ClaudeMonitor(home: home)
        var states = monitor.poll()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.id, "claude:\(uuid)")
        XCTAssertEqual(states.first?.harness, .claude)
        XCTAssertEqual(states.first?.status, .thinking)
        XCTAssertEqual(states.first?.name, "repo · \(uuid.prefix(8))")
        let title = #"{"type":"ai-title","aiTitle":"Named session","sessionId":"\#(uuid)"}"#
        try Data((title + "\n").utf8).append(to: file)
        let toolUse = #"{"type":"assistant","sessionId":"\#(uuid)","timestamp":"2026-10-30T00:00:05.000Z","message":{"content":[{"type":"tool_use","name":"Edit"}]}}"#
        try Data((toolUse + "\n").utf8).append(to: file)
        states = monitor.poll()
        XCTAssertEqual(states.first?.status, .working)
        XCTAssertEqual(states.first?.name, "Named session")
        XCTAssertNotNil(states.first?.updatedAt)
    }

    func testOpenCodeSessionStatusMapping() {
        XCTAssertEqual(OpenCodeReducer.sessionStatus(["type": "busy"]), .thinking)
        XCTAssertEqual(OpenCodeReducer.sessionStatus(["type": "retry"]), .thinking)
        XCTAssertEqual(OpenCodeReducer.sessionStatus(["type": "idle"]), .idle)
        XCTAssertNil(OpenCodeReducer.sessionStatus(["type": "unknown"]))
    }

    func testOpenCodeEventMapping() {
        let asked: [String: Any] = ["type": "permission.asked", "properties": ["sessionID": "ses_a"]]
        XCTAssertEqual(OpenCodeReducer.event(asked)?.1, .waiting)
        XCTAssertEqual(OpenCodeReducer.event(asked)?.0, "ses_a")
        let replied: [String: Any] = ["type": "permission.replied", "properties": ["sessionID": "ses_a"]]
        XCTAssertEqual(OpenCodeReducer.event(replied)?.1, .thinking)
        let idle: [String: Any] = ["type": "session.idle", "properties": ["sessionID": "ses_a"]]
        XCTAssertEqual(OpenCodeReducer.event(idle)?.1, .idle)
        let aborted: [String: Any] = ["type": "session.error", "properties": ["sessionID": "ses_a", "error": ["name": "MessageAbortedError"]]]
        XCTAssertEqual(OpenCodeReducer.event(aborted)?.1, .interrupted)
        let failed: [String: Any] = ["type": "session.error", "properties": ["sessionID": "ses_a", "error": ["name": "ProviderAuthError"]]]
        XCTAssertEqual(OpenCodeReducer.event(failed)?.1, .failed)
        let unrelated: [String: Any] = ["type": "lsp.updated", "properties": [:]]
        XCTAssertNil(OpenCodeReducer.event(unrelated))
    }

    func testOpenCodeCompletionTransition() {
        XCTAssertEqual(OpenCodeReducer.transition(from: .thinking, to: .idle), .completed)
        XCTAssertEqual(OpenCodeReducer.transition(from: .waiting, to: .idle), .completed)
        XCTAssertEqual(OpenCodeReducer.transition(from: .idle, to: .idle), .idle)
        XCTAssertEqual(OpenCodeReducer.transition(from: .working, to: .failed), .failed)
        XCTAssertEqual(OpenCodeReducer.transition(from: .completed, to: .idle), .idle)
    }

    func testSelectionFiltersByHarness() {
        let now = Date()
        let codex = ThreadState(id: "t1", name: "Codex work", status: .working, updatedAt: now, harness: .codex)
        let claude = ThreadState(id: "c1", name: "Claude work", status: .failed, updatedAt: now.addingTimeInterval(5), harness: .claude)
        XCTAssertEqual(Selection.status(for: nil, harness: .claude, threads: [codex, claude]), .failed)
        XCTAssertEqual(Selection.status(for: nil, harness: .codex, threads: [codex, claude]), .working)
        XCTAssertEqual(Selection.status(for: nil, harness: .all, threads: [codex, claude]), .failed)
        XCTAssertEqual(Selection.status(for: "*", harness: .codex, threads: [codex, claude]), .working)
        XCTAssertEqual(Selection.status(for: "c1", harness: .codex, threads: [codex, claude]), .offline)
        XCTAssertEqual(Selection.status(for: "c1", harness: .all, threads: [codex, claude]), .failed)
        let waitingClaude = ThreadState(id: "c2", name: "Waiting", status: .waiting, updatedAt: now, harness: .claude)
        XCTAssertEqual(Selection.status(for: "*", harness: .claude, threads: [claude, waitingClaude]), .waiting)
    }

    func testPetInstanceRoundTripsHarness() throws {
        var instance = PetInstance(petID: "codex", threadID: "*", x: 1, y: 2)
        instance.harness = .opencode
        let data = try JSONEncoder().encode(instance)
        let decoded = try JSONDecoder().decode(PetInstance.self, from: data)
        XCTAssertEqual(decoded.harness, .opencode)
        let legacy = try JSONDecoder().decode(PetInstance.self, from: #"{"id":"00000000-0000-0000-0000-000000000001","petID":"codex","threadID":"t1","x":1,"y":2}"#.data(using: .utf8)!)
        XCTAssertNil(legacy.harness)
    }
}

private extension Data {
    func append(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: self)
        } else {
            try write(to: url)
        }
    }
}
