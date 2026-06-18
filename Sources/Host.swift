import Foundation

/// A machine Claudette polls for Claude Code sessions: the local Mac, or a
/// remote box reached over **key-based** SSH (passwordless).
///
/// Remote polling runs `ssh user@host '<claude> agents --json'` with
/// `BatchMode=yes`, so it never prompts for a password — set up an SSH key (and,
/// ideally, an `ssh-agent`/`ControlMaster` connection) on the remote first.
struct Host: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case local, ssh }

    let id: String
    var kind: Kind
    var label: String
    var enabled: Bool

    // SSH-only — ignored when `kind == .local`.
    var user: String
    var hostname: String
    var port: Int
    var identityFile: String      // empty = ssh's default key lookup
    var remoteClaudePath: String  // empty = resolve `claude` via a remote login shell

    /// Stable id of the implicit local host.
    static let localID = "local"

    /// The always-present local machine. Not persisted; reconstructed each launch.
    static var local: Host {
        Host(id: localID, kind: .local, label: "This Mac", enabled: true,
             user: "", hostname: "", port: 22, identityFile: "", remoteClaudePath: "")
    }

    /// A blank SSH host ready to be filled in by the add form.
    static func newRemote() -> Host {
        Host(id: UUID().uuidString, kind: .ssh, label: "", enabled: true,
             user: "", hostname: "", port: 22, identityFile: "", remoteClaudePath: "")
    }

    /// `user@host:port` style summary for display (port shown only when non-default).
    var connectionSummary: String {
        let target = user.isEmpty ? hostname : "\(user)@\(hostname)"
        return port == 22 ? target : "\(target):\(port)"
    }

    /// A non-empty display name, falling back to the connection summary.
    var displayLabel: String {
        if !label.isEmpty { return label }
        return kind == .local ? "This Mac" : (connectionSummary.isEmpty ? "Remote" : connectionSummary)
    }
}
