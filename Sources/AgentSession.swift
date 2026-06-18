import Foundation

/// One background Claude Code session, as emitted by `claude agents --json`.
///
/// Decoded fields mirror the CLI output exactly. `status` and `pid` are present
/// for live sessions (plain `--json`) but absent from `--json --all`, so both are
/// optional. `hostID`/`hostLabel` are *not* part of the CLI output — the poller
/// stamps them after decoding so sessions can be attributed to the machine they
/// came from.
struct AgentSession: Codable, Identifiable, Hashable {
    let agentID: String
    let sessionId: String
    let cwd: String
    let name: String
    let kind: String
    let startedAt: Double          // epoch milliseconds
    let state: String              // working | done | failed | stopped | blocked
    let status: String?            // busy | idle  (nil in --all output)
    let pid: Int?

    // Stamped post-decode by the poller; never read from JSON.
    var hostID: String = Host.localID
    var hostLabel: String = ""

    /// Only the CLI fields participate in (de)coding; host fields keep their defaults.
    private enum CodingKeys: String, CodingKey {
        case agentID = "id"
        case sessionId, cwd, name, kind, startedAt, state, status, pid
    }

    /// Interactive sessions are shaped differently from background agents: they're
    /// keyed by `pid` (no `id`), and carry no `name`/`state` — only a `status`.
    /// Decode defensively so one interactive entry can't fail the whole list:
    /// fall back to `pid`/`sessionId` for the id and default the missing fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        cwd       = try c.decode(String.self, forKey: .cwd)
        kind      = try c.decode(String.self, forKey: .kind)
        startedAt = try c.decode(Double.self, forKey: .startedAt)
        status    = try c.decodeIfPresent(String.self, forKey: .status)
        pid       = try c.decodeIfPresent(Int.self, forKey: .pid)
        name      = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        state     = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        agentID   = try c.decodeIfPresent(String.self, forKey: .agentID)
                    ?? pid.map(String.init) ?? sessionId
    }

    /// Globally unique across hosts — two machines can emit the same agent id, so
    /// the host is folded in for `Identifiable`, notification keys, and grouping.
    var id: String { hostID == Host.localID ? agentID : "\(hostID)/\(agentID)" }

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
