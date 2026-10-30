import Foundation

/// Reduces opencode server responses and SSE events without sending prompts or approving tools.
public enum OpenCodeReducer {
    /// Turn evidence older than this decays to idle, matching the transcript tailer:
    /// storage has no crash marker, so an abandoned turn must not stay active forever.
    public static let staleInterval: TimeInterval = 900

    /// Runtime evidence recovered from shared storage for one session.
    public struct TurnEvidence: Sendable {
        public var updatedAt: Date
        public var latestPartType: String?
        public var latestMessageRole: String?
        /// The newest assistant message carries `time.completed` or `finish` once its turn ends.
        public var turnCompleted: Bool
        public init(updatedAt: Date, latestPartType: String? = nil, latestMessageRole: String? = nil, turnCompleted: Bool = false) {
            self.updatedAt = updatedAt; self.latestPartType = latestPartType; self.latestMessageRole = latestMessageRole; self.turnCompleted = turnCompleted
        }
    }

    /// Maps shared-storage turn evidence to a live status. `nil` means no live signal,
    /// letting the server poll and SSE stream decide as before.
    public static func turn(_ evidence: TurnEvidence, now: Date) -> PetStatus? {
        guard now.timeIntervalSince(evidence.updatedAt) < staleInterval else { return nil }
        if evidence.latestMessageRole == "assistant", evidence.turnCompleted { return nil }
        return evidence.latestPartType == "tool" ? .working : .thinking
    }

    /// Maps a 2.x `/api/session/active` entry (`{ "type": "running" }`) or a 1.x
    /// `/session/status` entry (`{ "type": "idle" | "retry" | "busy" }`) to a pet status.
    public static func sessionStatus(_ payload: [String: Any]) -> PetStatus? {
        switch payload["type"] as? String {
        case "running", "busy", "retry": return .thinking
        case "idle": return .idle
        default: return nil
        }
    }
    /// Maps an SSE event envelope. opencode 2.x puts fields under `data`; 1.x used
    /// `properties`. The event names also changed: execution.* replaces session.idle for
    /// turn boundaries, and tool events expose working state.
    public static func event(_ message: [String: Any]) -> (String, PetStatus)? {
        guard let type = message["type"] as? String,
              let p = (message["data"] as? [String: Any]) ?? (message["properties"] as? [String: Any]),
              let id = p["sessionID"] as? String else { return nil }
        switch type {
        case "permission.asked": return (id, .waiting)
        case "permission.replied", "permission.rejected": return (id, .thinking)
        case "session.execution.started", "session.step.started", "session.retry.scheduled": return (id, .thinking)
        case "session.tool.called": return (id, .working)
        case "session.tool.success", "session.tool.failed", "session.step.ended": return (id, .thinking)
        case "session.execution.succeeded", "session.idle": return (id, .idle)
        case "session.execution.failed": return (id, .failed)
        case "session.execution.interrupted": return (id, .interrupted)
        case "session.error":
            let name = (p["error"] as? [String: Any])?["name"] as? String
            return (id, name == "MessageAbortedError" ? .interrupted : .failed)
        default: return nil
        }
    }
    /// A session that just left an active state finished its turn; the pet plays its review animation.
    public static func transition(from previous: PetStatus, to next: PetStatus) -> PetStatus {
        if next == .idle, [.working, .thinking, .waiting].contains(previous) { return .completed }
        return next
    }
}
