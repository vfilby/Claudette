import Foundation
import Combine

/// Polls `claude agents --json` on an interval, publishes the parsed sessions,
/// and detects state transitions to drive notifications.
final class AgentPoller: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published var pollInterval: TimeInterval = 4 {
        didSet { restartTimer() }
    }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.vfilby.Claudette.poll", qos: .utility)
    private let notifier = NotificationManager()

    /// Last seen state keyed by session id, used to fire transition notifications.
    private var previousState: [String: SessionCategory] = [:]
    private var primed = false   // skip notifications on the very first poll

    // MARK: Derived views

    var workingCount: Int { sessions.filter { $0.category == .working }.count }
    var needsInputCount: Int { sessions.filter { $0.category == .needsInput }.count }

    /// Sessions grouped by rolled-up project path, each group sorted by category.
    var byProject: [(project: String, name: String, sessions: [AgentSession])] {
        let groups = Dictionary(grouping: sessions, by: { $0.projectPath })
        return groups.map { key, value in
            (project: key,
             name: URL(fileURLWithPath: key).lastPathComponent,
             sessions: value.sorted {
                 $0.category.sortRank != $1.category.sortRank
                     ? $0.category.sortRank < $1.category.sortRank
                     : $0.startedAt > $1.startedAt
             })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Lifecycle

    func start() {
        notifier.requestAuthorization()
        restartTimer()
        pollNow()
    }

    func pollNow() {
        queue.async { [weak self] in self?.runPoll() }
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollNow()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Polling

    private func runPoll() {
        guard let bin = Self.resolveClaudeBinary() else {
            publish(error: "Could not find the `claude` binary. Set its path in PATH.")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["agents", "--json"]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        do {
            try proc.run()
        } catch {
            publish(error: "Failed to launch claude: \(error.localizedDescription)")
            return
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            publish(error: "claude agents failed: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }

        do {
            let parsed = try JSONDecoder().decode([AgentSession].self, from: data)
            publish(sessions: parsed)
        } catch {
            publish(error: "Could not parse output: \(error.localizedDescription)")
        }
    }

    private func publish(sessions newSessions: [AgentSession]) {
        DispatchQueue.main.async {
            self.detectTransitions(newSessions)
            self.sessions = newSessions
            self.lastUpdated = Date()
            self.lastError = nil
        }
    }

    private func publish(error: String) {
        DispatchQueue.main.async {
            self.lastError = error
            self.lastUpdated = Date()
        }
    }

    /// Fires a notification when a session moves into a state worth surfacing.
    private func detectTransitions(_ newSessions: [AgentSession]) {
        defer {
            previousState = Dictionary(uniqueKeysWithValues: newSessions.map { ($0.id, $0.category) })
            primed = true
        }
        guard primed else { return }   // don't blast notifications on launch

        for s in newSessions {
            let old = previousState[s.id]
            let new = s.category
            guard old != new else { continue }

            switch new {
            case .needsInput:
                notifier.notify(title: "Claude needs input",
                                body: "\(s.projectName): \(s.name)", id: s.id)
            case .done where old == .working:
                notifier.notify(title: "✅ Session finished",
                                body: "\(s.projectName): \(s.name)", id: s.id)
            case .failed:
                notifier.notify(title: "❌ Session failed",
                                body: "\(s.projectName): \(s.name)", id: s.id)
            default:
                break
            }
        }
    }

    // MARK: Binary resolution

    /// Locates the `claude` CLI without relying on the app's (sparse) launch PATH.
    static func resolveClaudeBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a login shell's resolution of `command -v claude`.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = Pipe()
        do {
            try shell.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch { /* fall through */ }
        return nil
    }
}
