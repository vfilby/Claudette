import Foundation
import Combine

/// Owns the user's list of remote SSH hosts (persisted to `UserDefaults`) and
/// always surfaces the implicit local host alongside them.
final class HostStore: ObservableObject {
    @Published private(set) var remotes: [Host] = []

    private let key = "com.vfilby.Claudette.hosts"

    init() { load() }

    /// Local host first, then the configured remotes in insertion order.
    var allHosts: [Host] { [Host.local] + remotes }

    /// Hosts that should actually be polled (local is always enabled).
    var activeHosts: [Host] { allHosts.filter { $0.enabled } }

    /// Looks up a host (local or remote) by its stable id.
    func host(id: String) -> Host? { allHosts.first { $0.id == id } }

    /// True once at least one remote host is configured — used to decide whether
    /// the menu should show per-host headers.
    var hasRemotes: Bool { !remotes.isEmpty }

    // MARK: Mutations

    func add(_ host: Host) {
        remotes.append(host)
        save()
    }

    func remove(_ host: Host) {
        remotes.removeAll { $0.id == host.id }
        save()
    }

    func update(_ host: Host) {
        guard let i = remotes.firstIndex(where: { $0.id == host.id }) else { return }
        remotes[i] = host
        save()
    }

    func setEnabled(_ host: Host, _ on: Bool) {
        guard let i = remotes.firstIndex(where: { $0.id == host.id }) else { return }
        remotes[i].enabled = on
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Host].self, from: data) else { return }
        remotes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(remotes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
