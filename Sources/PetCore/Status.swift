import Foundation

public enum PetStatus: String, Codable, CaseIterable, Sendable {
    case idle, thinking, working, waiting, failed, interrupted, completed, offline
}

public struct ThreadState: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var status: PetStatus
    public var updatedAt: Date
    public init(id: String, name: String = "Codex", status: PetStatus = .idle, updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.status = status; self.updatedAt = updatedAt
    }
}

/// Reduces Codex app-server notifications and persisted rollout events without executing tools.
public enum StatusReducer {
    /// Runtime state wins over stale logs. Rollouts may enrich a current active
    /// state or preserve a just-completed outcome, but cannot revive an unloaded thread.
    public static func reconcile(runtime: ThreadState, rollout: ThreadState?) -> ThreadState {
        guard let rollout, rollout.id == runtime.id,
              rollout.updatedAt.timeIntervalSince1970 >= floor(runtime.updatedAt.timeIntervalSince1970) else { return runtime }
        var result = runtime
        if runtime.status == .thinking && rollout.status == .working {
            result.status = .working
        } else if runtime.status == .idle && [.completed, .failed, .interrupted].contains(rollout.status) {
            result.status = rollout.status
        } else { return runtime }
        result.updatedAt = max(runtime.updatedAt, rollout.updatedAt)
        return result
    }
    public static func runtime(_ value: [String: Any]) -> PetStatus {
        switch value["type"] as? String {
        case "active":
            let flags = value["activeFlags"] as? [String] ?? []
            return flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput") ? .waiting : .thinking
        case "idle": return .idle
        case "systemError": return .failed
        default: return .offline
        }
    }
    public static func notification(_ message: [String: Any]) -> (String, PetStatus)? {
        guard let method = message["method"] as? String, let p = message["params"] as? [String: Any],
              let id = p["threadId"] as? String else { return nil }
        switch method {
        case "thread/status/changed": return (id, runtime(p["status"] as? [String: Any] ?? [:]))
        case "turn/started": return (id, .thinking)
        case "turn/completed":
            let status = (p["turn"] as? [String: Any])?["status"] as? String
            return (id, status == "completed" ? .completed : status == "failed" ? .failed : status == "interrupted" ? .interrupted : .offline)
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/tool/requestUserInput": return (id, .waiting)
        case "item/started":
            let kind = (p["item"] as? [String: Any])?["type"] as? String ?? ""
            return (id, ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"].contains(kind) ? .working : .thinking)
        case "error": return (id, (p["willRetry"] as? Bool == true) ? .thinking : .failed)
        case "thread/closed", "thread/archived": return (id, .offline)
        default: return nil
        }
    }
    public static func rollout(_ message: [String: Any]) -> PetStatus? {
        let type = message["type"] as? String
        guard let p = message["payload"] as? [String: Any] else { return nil }
        let event = p["type"] as? String ?? ""
        if type == "event_msg" {
            switch event {
            case "task_started": return .thinking
            case "task_complete", "task_completed": return .completed
            case "task_failed", "error": return .failed
            case "turn_aborted": return .interrupted
            case "agent_reasoning", "agent_message": return .thinking
            default: return nil
            }
        }
        if type == "response_item" {
            switch event {
            case "function_call", "custom_tool_call": return .working
            case "function_call_output", "custom_tool_call_output", "reasoning": return .thinking
            default: return nil
            }
        }
        return nil
    }
}
