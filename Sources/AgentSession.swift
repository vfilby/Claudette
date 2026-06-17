import Foundation

/// One background Claude Code session, as emitted by `claude agents --json`.
///
/// Fields mirror the CLI output exactly. `status` and `pid` are present for live
/// sessions (plain `--json`) but absent from `--json --all`, so both are optional.
struct AgentSession: Codable, Identifiable, Hashable {
    let id: String
    let sessionId: String
    let cwd: String
    let name: String
    let kind: String
    let startedAt: Double          // epoch milliseconds
    let state: String              // working | done | failed | stopped | blocked
    let status: String?            // busy | idle  (nil in --all output)
    let pid: Int?

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000.0) }

    /// Collapses a worktree path back to its owning project, e.g.
    /// `/Users/me/Projects/foo/.claude/worktrees/bar` -> `/Users/me/Projects/foo`.
    var projectPath: String {
        if let r = cwd.range(of: "/.claude/worktrees/") {
            return String(cwd[..<r.lowerBound])
        }
        return cwd
    }

    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    /// True when the session is running inside an isolated git worktree.
    var isWorktree: Bool { cwd.contains("/.claude/worktrees/") }

    var category: SessionCategory { SessionCategory(state: state, status: status) }
}

/// The user-facing grouping ("category") used by the agent view.
enum SessionCategory: String, CaseIterable {
    case needsInput   = "Needs input"
    case working      = "Working"
    case done         = "Completed"
    case failed       = "Failed"
    case stopped      = "Stopped"
    case idle         = "Idle"

    init(state: String, status: String?) {
        switch state {
        case "blocked":            self = .needsInput
        case "working":            self = (status == "idle") ? .idle : .working
        case "done":               self = .done
        case "failed":             self = .failed
        case "stopped":            self = .stopped
        default:                   self = (status == "busy") ? .working : .idle
        }
    }

    /// SF Symbol shown next to each session row.
    var symbol: String {
        switch self {
        case .needsInput: return "exclamationmark.bubble.fill"
        case .working:    return "circle.dotted"
        case .done:       return "checkmark.circle.fill"
        case .failed:     return "xmark.octagon.fill"
        case .stopped:    return "stop.circle"
        case .idle:       return "moon.zzz"
        }
    }

    /// Sort weight for display: things needing attention float to the top.
    var sortRank: Int {
        switch self {
        case .needsInput: return 0
        case .working:    return 1
        case .failed:     return 2
        case .done:       return 3
        case .stopped:    return 4
        case .idle:       return 5
        }
    }
}
