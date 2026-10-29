import Foundation
import PetCore

/// One serial queue owns all transport and rollout state. Only snapshots cross to the UI.
final class Monitor {
    private let queue = DispatchQueue(label: "codex-harem.monitor", qos: .utility)
    private let rollout: RolloutMonitor
    private let executable: String
    private let home: URL
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var rpcThreads: [String: ThreadState] = [:]
    private var loadedThreads: [String: ThreadState] = [:]
    private var loadedDate = Date.distantPast
    private var loadedRequest: Int?
    private var readRequests: [Int: String] = [:]
    private var ready = false
    private var nextAttempt = Date.distantPast
    private var sequence = 10
    private var listRequest: Int?
    private var requestDate = Date.distantPast
    private var connectedAt = Date.distantPast
    private var diagnostic = "Session logs (connecting to Codex…)"
    var onUpdate: (([ThreadState], String) -> Void)?
    init(home: URL, executable: String) { self.home = home; self.executable = executable; rollout = RolloutMonitor(home: home) }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
    }
    func stop() { queue.sync { timer?.cancel(); timer = nil; disconnect() } }
    private func tick() {
        let logs = rollout.poll()
        if process == nil, Date() >= nextAttempt { connect() }
        if process != nil && ((!ready && Date().timeIntervalSince(connectedAt) > 8) || (listRequest != nil && Date().timeIntervalSince(requestDate) > 8) || ((loadedRequest != nil || !readRequests.isEmpty) && Date().timeIntervalSince(loadedDate) > 8)) {
            diagnostic = "Session logs · Codex connection timed out"; disconnect()
        }
        if ready && loadedRequest == nil && readRequests.isEmpty {
            sequence += 1; loadedRequest = sequence; loadedDate = Date()
            send(["id": sequence, "method": "thread/loaded/list"])
        }
        if ready && listRequest == nil {
            sequence += 1; listRequest = sequence; requestDate = Date()
            send(["id": sequence, "method": "thread/list", "params": ["limit": 100, "sortKey": "updated_at", "sourceKinds": ["cli", "vscode", "exec", "appServer", "unknown"], "useStateDbOnly": true]])
        }
        var combined = Dictionary(uniqueKeysWithValues: logs.map { ($0.id, $0) })
        if ready {
            for (id, state) in rpcThreads.merging(loadedThreads, uniquingKeysWith: { _, loaded in loaded }) {
                combined[id] = StatusReducer.reconcile(runtime: state, rollout: combined[id])
            }
        }
        let states = combined.values.sorted { $0.updatedAt > $1.updatedAt }
        let description = diagnostic
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(states, description) }
    }
    private func connect() {
        let task = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["app-server", "proxy", "--sock", home.appendingPathComponent("app-server-control/app-server-control.sock").path]
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stderr
        var environment = ProcessInfo.processInfo.environment; environment["CODEX_HOME"] = home.path; task.environment = environment
        // Drain stderr but don't expose arbitrary Codex logs in the menu.
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.queue.async { [weak self] in
                guard self?.process === task else { return }
                self?.receive(data)
            }
        }
        task.terminationHandler = { [weak self] finished in
            self?.queue.async { [weak self] in
                guard let self, self.process === finished else { return }
                self.diagnostic = "Session logs · shared Codex server unavailable"
                self.disconnect()
            }
        }
        do { try task.run(); process = task; input = stdin.fileHandleForWriting; connectedAt = Date()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_harem", "title": "Codex Harem", "version": "0.1.0"]]])
        } catch { diagnostic = "Session logs · cannot launch codex"; nextAttempt = Date().addingTimeInterval(10) }
    }
    private func disconnect() {
        let old = process
        (old?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (old?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil; ready = false; listRequest = nil; rpcThreads.removeAll(); loadedThreads.removeAll(); loadedRequest = nil; readRequests.removeAll(); buffer.removeAll()
        try? input?.close(); input = nil
        if let old, old.isRunning { old.terminate() }
        nextAttempt = Date().addingTimeInterval(10)
    }
    private func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10)
        do { try input?.write(contentsOf: data) } catch { disconnect() }
    }
    private func parseThread(_ thread: [String: Any]) -> ThreadState {
        let id = thread["id"] as? String ?? "unknown"
        return ThreadState(id: id, name: thread["name"] as? String ?? "Thread \(id.prefix(8))",
                           status: StatusReducer.runtime(thread["status"] as? [String: Any] ?? [:]),
                           updatedAt: Date(timeIntervalSince1970: (thread["updatedAt"] as? Double) ?? 0))
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]; buffer.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["id"] as? Int == 1 {
                guard object["error"] == nil else { diagnostic = "Session logs · Codex handshake rejected"; disconnect(); return }
                ready = true; diagnostic = "Connected to shared Codex server"; send(["method": "initialized"])
            } else if let id = object["id"] as? Int, id == loadedRequest {
                loadedRequest = nil
                if let result = object["result"] as? [String: Any], let ids = result["data"] as? [String] {
                    let retained = Set(ids)
                    loadedThreads = loadedThreads.filter { retained.contains($0.key) }
                    for thread in ids {
                        sequence += 1; readRequests[sequence] = thread
                        send(["id": sequence, "method": "thread/read", "params": ["threadId": thread, "includeTurns": false]])
                    }
                }
            } else if let id = object["id"] as? Int, let threadID = readRequests.removeValue(forKey: id) {
                if let result = object["result"] as? [String: Any], let thread = result["thread"] as? [String: Any] {
                    loadedThreads[threadID] = parseThread(thread)
                } else { loadedThreads[threadID] = nil }
            } else if let id = object["id"] as? Int, id == listRequest {
                listRequest = nil
                if let result = object["result"] as? [String: Any], let data = result["data"] as? [[String: Any]] {
                    var snapshot: [String: ThreadState] = [:]
                    for t in data {
                        guard let id = t["id"] as? String else { continue }
                        snapshot[id] = parseThread(t)
                    }
                    rpcThreads = snapshot
                } else { diagnostic = "Session logs · Codex thread/list rejected"; disconnect(); return }
            } else if let (id, status) = StatusReducer.notification(object) {
                var state = rpcThreads[id] ?? ThreadState(id: id)
                state.status = status; state.updatedAt = Date(); rpcThreads[id] = state
            }
        }
        if buffer.count > 8_388_608 { diagnostic = "Session logs · oversized Codex message"; disconnect() }
    }
}
