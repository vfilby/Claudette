import SwiftUI

@main
struct ClaudetteApp: App {
    @StateObject private var hosts: HostStore
    @StateObject private var poller: AgentPoller
    @StateObject private var updates = UpdateChecker()
    @AppStorage("menuBarIcon") private var iconRaw = MenuBarIcon.robot.rawValue

    init() {
        let store = HostStore()
        _hosts = StateObject(wrappedValue: store)
        _poller = StateObject(wrappedValue: AgentPoller(hosts: store))
        // Let the launcher resolve a session's host so remote sessions open over SSH
        // instead of falling back to a local shell.
        SessionLauncher.hostResolver = { [weak store] id in store?.host(id: id) }
    }

    private var icon: MenuBarIcon { MenuBarIcon(rawValue: iconRaw) ?? .robot }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(poller: poller, hosts: hosts, updates: updates)
                .onAppear {
                    poller.start()
                    updates.start()
                }
        } label: {
            label
            if poller.workingCount + poller.needsInputCount > 0 {
                Text("\(poller.workingCount + poller.needsInputCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Glyph reflects the most urgent state across all sessions.
    @ViewBuilder
    private var label: some View {
        let needsInput = poller.needsInputCount > 0
        let working = poller.workingCount > 0
        if let symbol = icon.symbol(needsInput: needsInput, working: working) {
            Image(systemName: symbol)
        } else if let emoji = icon.emoji {
            Text(emoji)
        } else {
            Image(systemName: "ant")
        }
    }
}
