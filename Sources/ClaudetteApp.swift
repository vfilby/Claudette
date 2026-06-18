import SwiftUI

@main
struct ClaudetteApp: App {
    @StateObject private var poller = AgentPoller()
    @AppStorage("menuBarIcon") private var iconRaw = MenuBarIcon.robot.rawValue

    private var icon: MenuBarIcon { MenuBarIcon(rawValue: iconRaw) ?? .robot }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(poller: poller)
                .onAppear { poller.start() }
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
