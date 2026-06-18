import SwiftUI

struct MenuContentView: View {
    @ObservedObject var poller: AgentPoller
    @ObservedObject var hosts: HostStore

    @State private var managingHosts = false
    @AppStorage("menuBarIcon") private var iconRaw = MenuBarIcon.robot.rawValue

    private var icon: MenuBarIcon { MenuBarIcon(rawValue: iconRaw) ?? .robot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if managingHosts {
                HostsView(poller: poller, hosts: hosts, onClose: { managingHosts = false })
            } else {
                sessionList
            }
        }
        .frame(width: 340)
    }

    // MARK: Session list

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            let groups = poller.byHost
            if groups.isEmpty {
                emptyRow
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            HostSection(group: group, showHeader: showHostHeaders)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: listHeight)
            }

            Divider()
            footer
        }
    }

    /// Show per-host headers only once there's more than the local machine in play.
    private var showHostHeaders: Bool {
        hosts.hasRemotes
    }

    /// Explicit, content-adaptive height for the session list. Inside a
    /// fit-to-content `MenuBarExtra` window a bare `ScrollView` collapses to a
    /// tiny intrinsic height, hiding most sessions; sizing it ourselves up to a
    /// cap keeps every session visible until the list is genuinely long.
    private var listHeight: CGFloat {
        let hostHeader: CGFloat = 24       // per-host header (shown only with remotes)
        let groupHeader: CGFloat = 28      // folder row
        let sessionRow: CGFloat = 44       // one session
        let groupSpacing: CGFloat = 12     // VStack spacing between groups
        let verticalPadding: CGFloat = 16  // .padding(.vertical, 8) top+bottom

        let groups = poller.byHost
        let projectCount = groups.reduce(0) { $0 + $1.projects.count }
        let sessionCount = groups.reduce(0) { sum, host in
            sum + host.projects.reduce(0) { $0 + $1.sessions.count }
        }

        var content = verticalPadding
        content += CGFloat(projectCount) * groupHeader
        content += CGFloat(sessionCount) * sessionRow
        content += CGFloat(max(0, groups.count - 1)) * groupSpacing
        if showHostHeaders {
            content += CGFloat(groups.count) * hostHeader
        }

        return min(max(content, 60), 480)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            if let emoji = icon.emoji {
                Text(emoji)
            } else {
                Image(systemName: icon.previewSymbol ?? "ant.fill")
            }
            Text("Claudette").font(.headline)
            Spacer()
            if poller.needsInputCount > 0 {
                pill("\(poller.needsInputCount) need input", color: .orange)
            }
            if poller.workingCount > 0 {
                pill("\(poller.workingCount) working", color: .blue)
            }
        }
        .padding(10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = poller.lastUpdated {
                Text("Updated \(updated, style: .time)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TerminalPicker()
            Button { managingHosts = true } label: { Image(systemName: "server.rack") }
                .buttonStyle(.borderless)
                .help("Manage remote hosts")
            iconPicker
            Button { poller.pollNow() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(10)
    }

    private var iconPicker: some View {
        Menu {
            Picker("Menu Bar Icon", selection: $iconRaw) {
                ForEach(MenuBarIcon.allCases) { option in
                    Label {
                        Text(option.label)
                    } icon: {
                        if let emoji = option.emoji {
                            Text(emoji)
                        } else if let symbol = option.previewSymbol {
                            Image(systemName: symbol)
                        }
                    }
                    .tag(option.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose menu bar icon")
    }

    private func errorRow(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
    }

    private var emptyRow: some View {
        Text("No active sessions")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Host section

private struct HostSection: View {
    let group: AgentPoller.HostGroup
    let showHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack(spacing: 6) {
                    Image(systemName: group.isLocal ? "laptopcomputer" : "server.rack")
                        .font(.caption)
                    Text(group.label).font(.subheadline.weight(.bold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }

            if let error = group.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            ForEach(group.projects) { project in
                ProjectSection(group: project)
            }
        }
    }
}

/// Lets the user choose which terminal `Open in agent view` launches.
private struct TerminalPicker: View {
    @AppStorage("terminalApp") private var terminalApp: String = TerminalApp.auto.rawValue

    var body: some View {
        Menu {
            ForEach(TerminalApp.selectable) { term in
                Button {
                    terminalApp = term.rawValue
                } label: {
                    HStack {
                        Text(term.displayName)
                        if term.rawValue == terminalApp { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "macwindow")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Open sessions in: \(TerminalApp(rawValue: terminalApp)?.displayName ?? "Automatic")")
    }
}

private struct ProjectSection: View {
    let group: AgentPoller.ProjectGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").font(.caption).foregroundStyle(.secondary)
                Text(group.name).font(.subheadline.weight(.semibold))
                Text("\(group.sessions.count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            ForEach(group.sessions) { session in
                SessionRow(session: session)
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    @State private var hovering = false

    var body: some View {
        Button { SessionLauncher.open(cwd: session.projectPath) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: session.category.symbol)
                    .foregroundStyle(color)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(.callout)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(session.category.rawValue)
                        if session.isWorktree {
                            Text("· worktree")
                        }
                        Text("· \(session.startedDate, style: .relative)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.primary.opacity(0.08) : Color.clear)
        .onHover { hovering = $0 }
        .help("Open this session in the agent view")
    }

    private var color: Color {
        switch session.category {
        case .needsInput: return .orange
        case .working:    return .blue
        case .done:       return .green
        case .failed:     return .red
        case .stopped:    return .secondary
        case .idle:       return .secondary
        }
    }
}
