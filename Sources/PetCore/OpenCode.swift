import Foundation

/// Reduces opencode server responses and SSE events without sending prompts or approving tools.
public enum OpenCodeReducer {
    /// Maps a `/session/status` entry (`{ "type": "idle" | "retry" | "busy" }`) to a pet status.
    public static func sessionStatus(_ payload: [String: Any]) -> PetStatus? {
        switch payload["type"] as? String {
        case "busy", "retry": return .thinking
        case "idle": return .idle
        default: return nil
        }
    }
    /// Maps an SSE event envelope (`{ "type": ..., "properties": { sessionID, ... } }`).
    public static func event(_ message: [String: Any]) -> (String, PetStatus)? {
        guard let type = message["type"] as? String, let p = message["properties"] as? [String: Any],
              let id = p["sessionID"] as? String else { return nil }
        switch type {
        case "permission.asked": return (id, .waiting)
        case "permission.replied": return (id, .thinking)
        case "session.idle": return (id, .idle)
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
