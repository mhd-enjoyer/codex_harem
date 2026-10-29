import Foundation

/// Which agent harness a pet observes. `all` merges every provider's threads.
public enum Harness: String, Codable, CaseIterable, Sendable {
    case all, codex, claude, opencode
    public var displayName: String {
        switch self {
        case .all: return "All harnesses"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .opencode: return "opencode"
        }
    }
}
