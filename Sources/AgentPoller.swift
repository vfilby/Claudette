import Foundation
import Combine

/// Polls `claude agents --json` across every active host (the local Mac plus any
/// configured SSH remotes) on an interval, publishes the merged session list, and
/// detects state transitions to drive notifications.
final class AgentPoller: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastUpdated: Date?
    /// Per-host poll failure messages, keyed by `Host.id`.
    @Published private(set) var hostErrors: [String: String] = [:]
    @Published var pollInterval: TimeInterval = 4 {
        didSet { restartTimer() }
    }

    let hosts: HostStore

    private var timer: Timer?
    /// Concurrent so hosts are polled in parallel — one slow SSH box can't stall
    /// the others (each ssh call is capped by `ConnectTimeout`).
    private let queue = DispatchQueue(label: "com.vfilby.Claudette.poll",
                                      qos: .utility, attributes: .concurrent)
    private let notifier = NotificationManager()

    /// Guards against overlapping polls when a round runs longer than the interval.
    private let pollLock = NSLock()
    private var polling = false

    /// Last seen state keyed by session id, used to fire transition notifications.
    private var previousState: [String: SessionCategory] = [:]
    private var primed = false   // skip notifications on the very first poll

    init(hosts: HostStore) {
        self.hosts = hosts
    }

    // MARK: Derived views

    var workingCount: Int { sessions.filter { $0.category == .working }.count }
    var needsInputCount: Int { sessions.filter { $0.category == .needsInput }.count }

    /// A project folder within a single host, with its sessions sorted for display.
    struct ProjectGroup: Identifiable {
        let project: String
        let name: String
        let sessions: [AgentSession]
        var id: String { project }
    }

    /// One host's worth of state: its sessions rolled up by project, plus any error.
    struct HostGroup: Identifiable {
        let id: String
        let label: String
        let isLocal: Bool
        let error: String?
        let projects: [ProjectGroup]
    }

    /// Active hosts in order, each carrying its project groups and last error.
    /// Hosts with neither sessions nor an error are dropped so the menu stays tidy.
    var byHost: [HostGroup] {
        let sessionsByHost = Dictionary(grouping: sessions, by: { $0.hostID })
        return hosts.activeHosts.compactMap { host in
            let mine = sessionsByHost[host.id] ?? []
            let error = hostErrors[host.id]
            guard !mine.isEmpty || error != nil else { return nil }

            let projects = Dictionary(grouping: mine, by: { $0.projectPath })
                .map { key, value in
                    ProjectGroup(project: key,
                                 name: URL(fileURLWithPath: key).lastPathComponent,
                                 sessions: value.sorted(by: Self.displayOrder))
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            return HostGroup(id: host.id, label: host.displayLabel,
                             isLocal: host.kind == .local, error: error, projects: projects)
        }
    }

    /// Attention-needing sessions float up; ties break on most-recently-started.
    private static func displayOrder(_ a: AgentSession, _ b: AgentSession) -> Bool {
        a.category.sortRank != b.category.sortRank
            ? a.category.sortRank < b.category.sortRank
            : a.startedAt > b.startedAt
    }

    // MARK: Lifecycle

    func start() {
        notifier.requestAuthorization()
        restartTimer()
        pollNow()
    }

    func pollNow() {
        let targets = hosts.activeHosts   // read on the main thread
        queue.async { [weak self] in self?.runPoll(targets) }
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollNow()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// A poll failure carrying a user-facing message.
    struct PollError: Error { let message: String }

    /// Runs a single host's fetch off the main thread and reports the outcome.
    func test(_ host: Host, completion: @escaping (Result<Int, PollError>) -> Void) {
        queue.async {
            let result = Self.fetch(host: host)
            DispatchQueue.main.async {
                switch result {
                case .ok(let sessions): completion(.success(sessions.count))
                case .fail(let message): completion(.failure(PollError(message: message)))
                }
            }
        }
    }

    // MARK: Polling

    private func runPoll(_ targets: [Host]) {
        guard beginPoll() else { return }   // a poll is already in flight
        defer { endPoll() }

        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [AgentSession] = []
        var errors: [String: String] = [:]

        for host in targets {
            group.enter()
            queue.async {
                defer { group.leave() }
                let result = Self.fetch(host: host)
                lock.lock()
                switch result {
                case .ok(let sessions): collected.append(contentsOf: sessions)
                case .fail(let message): errors[host.id] = message
                }
                lock.unlock()
            }
        }
        group.wait()
        publish(sessions: collected, errors: errors)
    }

    private func beginPoll() -> Bool {
        pollLock.lock(); defer { pollLock.unlock() }
        if polling { return false }
        polling = true
        return true
    }

    private func endPoll() {
        pollLock.lock(); polling = false; pollLock.unlock()
    }

    /// Outcome of fetching one host's session list.
    private enum FetchResult {
        case ok([AgentSession])
        case fail(String)
    }

    /// Fetches and parses `claude agents --json` from a single host.
    private static func fetch(host: Host) -> FetchResult {
        let proc = Process()
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        switch host.kind {
        case .local:
            guard let bin = resolveClaudeBinary() else {
                return .fail("Could not find the `claude` binary. Set its path in PATH.")
            }
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = ["agents", "--json"]
        case .ssh:
            guard !host.hostname.isEmpty else { return .fail("No hostname configured.") }
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            proc.arguments = sshArguments(for: host)
        }

        do {
            try proc.run()
        } catch {
            let what = host.kind == .ssh ? "ssh" : "claude"
            return .fail("Failed to launch \(what): \(error.localizedDescription)")
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let raw = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .fail(friendlyError(raw, status: proc.terminationStatus, kind: host.kind))
        }

        do {
            var parsed = try JSONDecoder().decode([AgentSession].self, from: data)
            for i in parsed.indices {
                parsed[i].hostID = host.id
                parsed[i].hostLabel = host.displayLabel
            }
            return .ok(parsed)
        } catch {
            return .fail("Could not parse session list: \(error.localizedDescription)")
        }
    }

    // MARK: SSH command construction

    private static func sshArguments(for host: Host) -> [String] {
        var args = [
            "-o", "BatchMode=yes",                    // never prompt — key-based auth only
            "-o", "ConnectTimeout=8",                 // fail fast on an unreachable host
            "-o", "StrictHostKeyChecking=accept-new", // trust-on-first-use, pin thereafter
        ]
        if host.port != 22 {
            args += ["-p", String(host.port)]
        }
        if !host.identityFile.isEmpty {
            args += ["-i", (host.identityFile as NSString).expandingTildeInPath]
        }
        args.append(host.user.isEmpty ? host.hostname : "\(host.user)@\(host.hostname)")
        args.append(remoteCommand(for: host))
        return args
    }

    /// The command run on the remote. With an explicit path we invoke it directly;
    /// otherwise we go through a login shell so the remote user's PATH applies
    /// (ssh runs commands via a non-login shell, which often omits `claude`).
    private static func remoteCommand(for host: Host) -> String {
        if !host.remoteClaudePath.isEmpty {
            return "\(host.remoteClaudePath) agents --json"
        }
        return "bash -lc 'claude agents --json'"
    }

    /// Translates common SSH/remote failures into something actionable.
    private static func friendlyError(_ raw: String?, status: Int32, kind: Host.Kind) -> String {
        let message = (raw?.isEmpty == false) ? raw! : "exited with status \(status)"
        guard kind == .ssh else { return message }

        let lower = message.lowercased()
        if lower.contains("permission denied") {
            return "SSH auth failed — add your public key to the remote (passwordless)."
        }
        if lower.contains("could not resolve") || lower.contains("name or service not known") {
            return "Host not found — check the hostname."
        }
        if lower.contains("timed out") || lower.contains("operation timed out") {
            return "Connection timed out — host unreachable?"
        }
        if lower.contains("connection refused") {
            return "Connection refused — is sshd running on that port?"
        }
        if lower.contains("command not found") || lower.contains("no such file") {
            return "`claude` not found on the remote — set its path in host settings."
        }
        if lower.contains("host key verification failed") {
            return "Host key changed — fix the remote's entry in ~/.ssh/known_hosts."
        }
        return message
    }

    // MARK: Publishing

    private func publish(sessions newSessions: [AgentSession], errors: [String: String]) {
        DispatchQueue.main.async {
            self.detectTransitions(newSessions)
            self.sessions = newSessions
            self.hostErrors = errors
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

            // Prefix remote sessions with the host so notifications are unambiguous.
            let hostTag = s.hostID == Host.localID ? "" : "[\(s.hostLabel)] "

            switch new {
            case .needsInput:
                notifier.notify(title: "Claude needs input",
                                body: "\(hostTag)\(s.projectName): \(s.name)", id: s.id, cwd: s.projectPath)
            case .done where old == .working:
                notifier.notify(title: "✅ Session finished",
                                body: "\(hostTag)\(s.projectName): \(s.name)", id: s.id, cwd: s.projectPath)
            case .failed:
                notifier.notify(title: "❌ Session failed",
                                body: "\(hostTag)\(s.projectName): \(s.name)", id: s.id, cwd: s.projectPath)
            default:
                break
            }
        }
    }

    // MARK: Binary resolution

    /// Locates the local `claude` CLI without relying on the app's (sparse) launch PATH.
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
