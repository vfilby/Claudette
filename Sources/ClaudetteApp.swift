import SwiftUI

@main
struct ClaudetteApp: App {
    @StateObject private var poller = AgentPoller()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(poller: poller)
                .onAppear { poller.start() }
        } label: {
            Image(systemName: menuSymbol)
            if poller.workingCount + poller.needsInputCount > 0 {
                Text("\(poller.workingCount + poller.needsInputCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Glyph reflects the most urgent state across all sessions.
    private var menuSymbol: String {
        if poller.needsInputCount > 0 { return "exclamationmark.bubble.fill" }
        if poller.workingCount > 0 { return "ant.fill" }
        return "ant"
    }
}
