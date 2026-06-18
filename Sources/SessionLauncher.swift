import Foundation
import AppKit

/// Opens a terminal "at" a background Claude Code session.
///
/// Background agents are daemon workers, not foreground TTY processes, so there is
/// no pane/window to switch to and `claude --resume <id>` refuses them ("Use
/// `claude agents` to find and attach to it"). The canonical destination is therefore
/// the interactive **agent view** (`claude agents`), which we filter via `--cwd` to
/// the session's project so the target lands in a short, focused list.
///
/// `--cwd` matches by *project root* and rolls worktree sessions up under their parent,
/// so callers pass `AgentSession.projectPath` (not the raw worktree `cwd`, which `--cwd`
/// would not match).
enum SessionLauncher {

    /// Opens the agent view filtered to `cwd` (a project root path) in the
    /// user's preferred terminal.
    static func open(cwd: String) {
        guard let bin = AgentPoller.resolveClaudeBinary() else {
            NSSound.beep()
            return
        }
        // `exec` so the window's lifetime tracks the agent view, not a lingering shell.
        let command = "cd \(shellQuote(cwd)) && exec \(shellQuote(bin)) agents --cwd \(shellQuote(cwd))"
        TerminalApp.current.run(shellCommand: command)
    }

    // MARK: Escaping

    /// Wraps a string in single quotes for /bin/sh, escaping embedded single quotes.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// A terminal emulator Claudette knows how to launch a command in.
///
/// Adding a terminal is a one-line affair: give it a `bundleID` and a `launch`
/// strategy. Most modern terminals accept a program to run via argv (Ghostty,
/// Alacritty, kitty, WezTerm); the two AppleScriptable Apple/iTerm terminals get a
/// dedicated path; anything else falls back to a `.command` file opened by whatever
/// terminal owns that file type — so even unlisted terminals work as the system default.
enum TerminalApp: String, CaseIterable, Identifiable {
    case auto            // pick the best installed terminal
    case ghostty
    case iterm
    case appleTerminal
    case kitty
    case wezterm
    case alacritty
    case systemDefault   // hand a .command file to the OS default handler

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:          return "Automatic"
        case .ghostty:       return "Ghostty"
        case .iterm:         return "iTerm"
        case .appleTerminal: return "Terminal"
        case .kitty:         return "kitty"
        case .wezterm:       return "WezTerm"
        case .alacritty:     return "Alacritty"
        case .systemDefault: return "System default"
        }
    }

    /// Bundle identifier used to locate the app (nil for the synthetic cases).
    var bundleID: String? {
        switch self {
        case .ghostty:       return "com.mitchellh.ghostty"
        case .iterm:         return "com.googlecode.iterm2"
        case .appleTerminal: return "com.apple.Terminal"
        case .kitty:         return "net.kovidgoyal.kitty"
        case .wezterm:       return "com.github.wez.wezterm"
        case .alacritty:     return "org.alacritty"
        case .auto, .systemDefault: return nil
        }
    }

    var appURL: URL? {
        guard let id = bundleID else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    var isInstalled: Bool {
        switch self {
        case .auto, .systemDefault: return true
        default:                    return appURL != nil
        }
    }

    /// The user's persisted choice, defaulting to `.auto`.
    static var current: TerminalApp {
        let raw = UserDefaults.standard.string(forKey: "terminalApp") ?? ""
        return TerminalApp(rawValue: raw) ?? .auto
    }

    /// Terminals offered in the picker: the synthetic options plus whatever is installed.
    static var selectable: [TerminalApp] {
        allCases.filter { $0 == .auto || $0 == .systemDefault || $0.isInstalled }
    }

    /// Priority order used to resolve `.auto`.
    private static let autoPriority: [TerminalApp] =
        [.ghostty, .iterm, .kitty, .wezterm, .alacritty, .appleTerminal]

    /// Resolves `.auto` to a concrete terminal, falling back to the system default.
    func resolved() -> TerminalApp {
        guard self == .auto else { return self }
        return Self.autoPriority.first(where: \.isInstalled) ?? .systemDefault
    }

    // MARK: Launching

    func run(shellCommand command: String) {
        let term = resolved()
        switch term {
        case .ghostty, .alacritty:
            term.launchArgv(["-e", "/bin/sh", "-c", command])
        case .kitty:
            term.launchArgv(["/bin/sh", "-c", command])
        case .wezterm:
            term.launchArgv(["start", "--", "/bin/sh", "-c", command])
        case .iterm:
            Self.runITerm(command)
        case .appleTerminal:
            Self.runAppleTerminal(command)
        case .auto, .systemDefault:
            Self.runCommandFile(command)
        }
    }

    /// Opens a fresh instance of the app, passing argv through to its binary.
    private func launchArgv(_ args: [String]) {
        guard let url = appURL else { TerminalApp.runCommandFile(args.last ?? ""); return }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("[Claudette] \(self.displayName) launch failed: \(error.localizedDescription)") }
        }
    }

    private static func runAppleTerminal(_ command: String) {
        runAppleScript("""
        tell application "Terminal"
            activate
            do script "\(appleScriptEscape(command))"
        end tell
        """)
    }

    private static func runITerm(_ command: String) {
        runAppleScript("""
        tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window to write text "\(appleScriptEscape(command))"
        end tell
        """)
    }

    /// Universal fallback: write an executable `.command` script and let the OS open it
    /// in whichever terminal owns that file type (covers Warp and any unlisted terminal).
    private static func runCommandFile(_ command: String) {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("claudette-open-\(abs(command.hashValue)).command")
        let body = "#!/bin/sh\n\(command)\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("[Claudette] command-file fallback failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private static func runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            try? proc.run()
        }
    }

    /// Escapes a string for embedding inside an AppleScript double-quoted literal.
    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
