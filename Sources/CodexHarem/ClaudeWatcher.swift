import Foundation
import PetCore

/// One serial queue tails Claude Code transcripts. Only snapshots cross to the UI.
final class ClaudeWatcher {
    private let queue = DispatchQueue(label: "codex-harem.claude", qos: .utility)
    private let monitor: ClaudeMonitor
    private var timer: DispatchSourceTimer?
    private var diagnostic = "Claude Code · reading session logs…"
    var onUpdate: (([ThreadState], String) -> Void)?
    init(home: URL) { monitor = ClaudeMonitor(home: home) }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
    }
    func stop() { queue.sync { timer?.cancel(); timer = nil } }
    private func tick() {
        let states = monitor.poll()
        diagnostic = states.isEmpty ? "Claude Code · no session transcripts" : "Claude Code · \(states.count) recent sessions"
        let description = diagnostic
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(states, description) }
    }
}
