import Foundation
import Darwin
import PetCore

/// Owns one `opencode serve` child process, its SSE event stream, and 1 Hz status polls.
/// Only ThreadState snapshots cross to the UI.
final class OpenCodeWatcher {
    private let queue = DispatchQueue(label: "codex-harem.opencode", qos: .utility)
    private let executable: String
    private var process: Process?
    private var port = 0
    private var timer: DispatchSourceTimer?
    private var retryAt = Date.distantPast
    private var sessions: [String: ThreadState] = [:]
    private var waiting = Set<String>()
    private var previous: [String: PetStatus] = [:]
    private var sseSession: URLSession?
    private var sseTask: URLSessionDataTask?
    private var sseBuffer = Data()
    private var pollSession: URLSession?
    private var diagnostic = "opencode · starting server…"
    var onUpdate: (([ThreadState], String) -> Void)?
    init(executable: String) { self.executable = executable }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
    }
    func stop() { queue.sync { timer?.cancel(); timer = nil; disconnect(retry: false) } }
    private func tick() {
        if process == nil {
            if Date() >= retryAt { startServer() }
            return
        }
        if sseTask == nil { connectSSE() }
        poll()
        emit()
    }
    private func startServer() {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            diagnostic = "opencode · CLI not found; Codex and Claude Code still work"
            retryAt = Date().addingTimeInterval(30)
            emit()
            return
        }
        guard let chosen = Self.freePort() else {
            diagnostic = "opencode · no free local port"; retryAt = Date().addingTimeInterval(10); emit(); return
        }
        let task = Process(), stdout = Pipe(), stderr = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["serve", "--port", String(chosen), "--hostname", "127.0.0.1"]
        task.standardOutput = stdout; task.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        task.terminationHandler = { [weak self] finished in
            self?.queue.async { [weak self] in
                guard let self, self.process === finished else { return }
                self.diagnostic = "opencode · server unavailable, retrying"
                self.disconnect(retry: true)
            }
        }
        do { try task.run() } catch {
            diagnostic = "opencode · cannot launch CLI"; retryAt = Date().addingTimeInterval(10); emit(); return
        }
        process = task; port = chosen
        diagnostic = "opencode · starting server…"
        let pollConfig = URLSessionConfiguration.ephemeral
        pollConfig.connectionProxyDictionary = [:]
        pollConfig.timeoutIntervalForRequest = 5
        pollSession = URLSession(configuration: pollConfig)
        let sseConfig = URLSessionConfiguration.ephemeral
        sseConfig.connectionProxyDictionary = [:]
        sseConfig.timeoutIntervalForRequest = 86_400
        sseConfig.timeoutIntervalForResource = 86_400
        let handler = SSEHandler(queue: queue, onChunk: { [weak self] data in
            self?.receive(data)
        }, onFinish: { [weak self] in
            self?.sseTask = nil
        })
        sseSession = URLSession(configuration: sseConfig, delegate: handler, delegateQueue: nil)
    }
    private func disconnect(retry: Bool) {
        process?.terminate(); process = nil
        sseTask?.cancel(); sseTask = nil
        sseSession?.invalidateAndCancel(); sseSession = nil
        pollSession?.finishTasksAndInvalidate(); pollSession = nil
        sessions.removeAll(); waiting.removeAll(); previous.removeAll()
        if retry { retryAt = Date().addingTimeInterval(10) }
    }
    private func request(_ path: String) -> URLRequest {
        let request = NSMutableURLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        if let password = ProcessInfo.processInfo.environment["OPENCODE_SERVER_PASSWORD"] {
            let credentials = Data("opencode:\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        return request as URLRequest
    }
    private func getJSON(_ path: String) -> Any? {
        guard let pollSession else { return nil }
        var payload: Any?
        let semaphore = DispatchSemaphore(value: 0)
        var request = request(path); request.timeoutInterval = 4
        pollSession.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let object = try? JSONSerialization.jsonObject(with: data) { payload = object }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        return payload
    }
    private func poll() {
        guard let list = getJSON("/session") as? [[String: Any]] else { return }
        diagnostic = "opencode · server on 127.0.0.1:\(port)"
        let statusMap = (getJSON("/session/status") as? [String: Any]) ?? [:]
        var result: [String: ThreadState] = [:]
        for record in list {
            guard let ses = record["id"] as? String else { continue }
            let id = "opencode:" + ses
            if let title = record["title"] as? String, !title.isEmpty { sessions[id]?.name = title }
            var stamp = sessions[id]?.updatedAt ?? Date()
            if let time = record["time"] as? [String: Any], let updated = time["updated"] as? Double {
                stamp = Date(timeIntervalSince1970: updated / 1000)
            }
            let raw = (statusMap[ses] as? [String: Any]).flatMap { OpenCodeReducer.sessionStatus($0) } ?? .idle
            let effective = waiting.contains(ses) ? .waiting : OpenCodeReducer.transition(from: previous[id] ?? .idle, to: raw)
            previous[id] = effective
            result[id] = ThreadState(id: id, name: sessions[id]?.name ?? "opencode · \(ses.prefix(12))", status: effective, updatedAt: stamp, harness: .opencode)
        }
        sessions = result
    }
    private func connectSSE() {
        guard let sseSession else { return }
        sseTask = sseSession.dataTask(with: request("/event"))
        sseTask?.resume()
    }
    private func receive(_ chunk: Data) {
        sseBuffer.append(chunk)
        while let end = sseBuffer.firstIndex(of: 10) {
            let line = sseBuffer[..<end]; sseBuffer.removeSubrange(...end)
            guard let text = String(data: line, encoding: .utf8) else { continue }
            guard text.hasPrefix("data:"), let object = (try? JSONSerialization.jsonObject(with: Data(text.dropFirst(5).utf8))) as? [String: Any] else { continue }
            guard let (ses, status) = OpenCodeReducer.event(object) else { continue }
            let id = "opencode:" + ses
            switch status {
            case .waiting: waiting.insert(ses)
            default: waiting.remove(ses)
            }
            var state = sessions[id] ?? ThreadState(id: id, name: "opencode · \(ses.prefix(12))", status: .idle, updatedAt: Date(), harness: .opencode)
            let effective = status == .waiting ? .waiting : OpenCodeReducer.transition(from: previous[id] ?? .idle, to: status)
            previous[id] = effective
            state.status = effective; state.updatedAt = Date()
            sessions[id] = state
        }
        if sseBuffer.count > 8_388_608 { sseBuffer.removeAll() }
        emit()
    }
    private func emit() {
        let states = sessions.values.sorted { $0.updatedAt > $1.updatedAt }
        let description = diagnostic
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(states, description) }
    }
    private static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else { return nil }
        var resolved = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: resolved.sin_port))
    }
}

/// URLSession delegate that forwards SSE stream chunks to the watcher queue.
private final class SSEHandler: NSObject, URLSessionDataDelegate {
    private let queue: DispatchQueue
    private let onChunk: (Data) -> Void
    private let onFinish: () -> Void
    init(queue: DispatchQueue, onChunk: @escaping (Data) -> Void, onFinish: @escaping () -> Void) {
        self.queue = queue; self.onChunk = onChunk; self.onFinish = onFinish
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onChunk(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.asyncAfter(deadline: .now() + 2, execute: onFinish)
    }
}
