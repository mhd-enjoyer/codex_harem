import XCTest
@testable import PetCore

final class PetCoreTests: XCTestCase {
    func testRuntimeNeverRevivesStaleLogActivity() {
        let now = Date(timeIntervalSince1970: 200)
        let oldWork = ThreadState(id: "a", status: .working, updatedAt: now.addingTimeInterval(-60))
        let newWork = ThreadState(id: "a", status: .working, updatedAt: now.addingTimeInterval(1))
        for state: PetStatus in [.offline, .idle, .waiting, .failed] {
            let runtime = ThreadState(id: "a", status: state, updatedAt: now)
            XCTAssertEqual(StatusReducer.reconcile(runtime: runtime, rollout: oldWork).status, state)
            XCTAssertEqual(StatusReducer.reconcile(runtime: runtime, rollout: newWork).status, state)
        }
        let active = ThreadState(id: "a", name: "Runtime title", status: .thinking, updatedAt: now)
        XCTAssertEqual(StatusReducer.reconcile(runtime: active, rollout: oldWork).status, .thinking)
        XCTAssertEqual(StatusReducer.reconcile(runtime: active, rollout: newWork).status, .working)
        XCTAssertEqual(StatusReducer.reconcile(runtime: active, rollout: newWork).name, "Runtime title")
        let idle = ThreadState(id: "a", status: .idle, updatedAt: now)
        let failure = ThreadState(id: "a", status: .failed, updatedAt: now.addingTimeInterval(0.5))
        XCTAssertEqual(StatusReducer.reconcile(runtime: idle, rollout: failure).status, .failed)
        var staleFailure = failure; staleFailure.updatedAt = now.addingTimeInterval(-1)
        XCTAssertEqual(StatusReducer.reconcile(runtime: idle, rollout: staleFailure).status, .idle)
    }

    func testTailDetectsAtomicReplacementLargerThanOldFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n{\"partial\":".utf8).write(to: url)
        var reader = JSONLTail()
        XCTAssertEqual(try reader.read(url).first.flatMap(StatusReducer.rollout), .thinking)
        let replacement = "{\"padding\":\"" + String(repeating: "x", count: 100) + "\"}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n"
        try Data(replacement.utf8).write(to: url, options: .atomic)
        let events = try reader.read(url)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last.flatMap(StatusReducer.rollout), .completed)
        XCTAssertTrue(try reader.read(url).isEmpty)
    }
    func testRuntimeAndTerminalStatus() {
        XCTAssertEqual(StatusReducer.runtime(["type": "active", "activeFlags": ["waitingOnApproval"]]), .waiting)
        XCTAssertEqual(StatusReducer.runtime(["type": "active", "activeFlags": ["waitingOnUserInput"]]), .waiting)
        XCTAssertEqual(StatusReducer.runtime(["type": "active", "activeFlags": []]), .thinking)
        XCTAssertEqual(StatusReducer.runtime(["type": "systemError"]), .failed)
        for (wire, expected) in [("completed", PetStatus.completed), ("failed", .failed), ("interrupted", .interrupted)] {
            let result = StatusReducer.notification(["method": "turn/completed", "params": ["threadId": "t", "turn": ["status": wire]]])
            XCTAssertEqual(result?.0, "t"); XCTAssertEqual(result?.1, expected)
        }
        XCTAssertEqual(StatusReducer.notification(["method": "turn/completed", "params": ["threadId": "t", "turn": [:]]])?.1, .offline)
        XCTAssertEqual(StatusReducer.notification(["method": "error", "params": ["threadId": "t", "willRetry": true]])?.1, .thinking)
        XCTAssertNil(StatusReducer.notification(["method": "unknown", "params": ["threadId": "t"]]))
    }
    func testInterleavedThreadsStayIndependent() {
        let threads = [ThreadState(id: "a", status: .thinking, updatedAt: Date(timeIntervalSince1970: 200)), ThreadState(id: "b", status: .failed, updatedAt: Date(timeIntervalSince1970: 100))]
        XCTAssertEqual(Selection.status(for: "a", threads: threads), .thinking)
        XCTAssertEqual(Selection.status(for: "b", threads: threads), .failed)
        XCTAssertEqual(Selection.status(for: nil, threads: threads), .thinking)
        XCTAssertEqual(Selection.status(for: "*", threads: threads), .thinking)
        XCTAssertEqual(Selection.status(for: "missing", threads: threads), .offline)
    }
    func testSpriteValidationAndContainment() throws {
        var pet = PetManifest(id: "custom", displayName: "Custom", spritesheetPath: "sheet.webp")
        try pet.validate(imageWidth: 1536, imageHeight: 1872)
        XCTAssertThrowsError(try pet.validate(imageWidth: 1537, imageHeight: 1872))
        pet.spritesheetPath = "../private.webp"
        XCTAssertThrowsError(try pet.sheetURL(relativeTo: URL(fileURLWithPath: "/tmp/pets/a")))
        pet.spriteVersionNumber = 3
        XCTAssertThrowsError(try pet.validate(imageWidth: 1536, imageHeight: 1872))
        pet.spriteVersionNumber = 1
        pet.animations = ["idle": Animation(frames: [99])]
        XCTAssertThrowsError(try pet.validate(imageWidth: 1536, imageHeight: 1872))
        XCTAssertEqual(Animation(frames: [0, 1, 2], fps: 2).frame(at: 1.5), 0)
    }
    func testTailPartialWritesAndTruncation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n{\"type\":".utf8).write(to: url)
        var reader = JSONLTail()
        let first = try reader.read(url)
        XCTAssertEqual(first.count, 1); XCTAssertEqual(StatusReducer.rollout(first[0]), .thinking)
        let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
        try handle.write(contentsOf: Data("\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n".utf8)); try handle.close()
        let second = try reader.read(url)
        XCTAssertEqual(second.count, 1); XCTAssertEqual(StatusReducer.rollout(second[0]), .completed)
        XCTAssertTrue(try reader.read(url).isEmpty)
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\"}}\n".utf8).write(to: url)
        XCTAssertEqual(try reader.read(url).first.flatMap(StatusReducer.rollout), .interrupted)
    }
    func testSessionDiscoveryAndLifecycle() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent("sessions/2026/10/30")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let id = UUID().uuidString.lowercased()
        let file = dir.appendingPathComponent("rollout-2026-10-30T01-00-00-\(id).jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/tmp/my-project\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8).write(to: file)
        let monitor = RolloutMonitor(home: home)
        let initial = monitor.poll()
        XCTAssertEqual(initial.count, 1); XCTAssertEqual(initial[0].id, id); XCTAssertTrue(initial[0].name.contains("my-project")); XCTAssertEqual(initial[0].status, .thinking)
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_failed\"}}\n".utf8)); try handle.close()
        XCTAssertEqual(monitor.poll().first?.status, .failed)
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(monitor.poll().isEmpty)
    }
}
