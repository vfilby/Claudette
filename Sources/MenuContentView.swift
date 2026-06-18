import SwiftUI

struct MenuContentView: View {
    @ObservedObject var poller: AgentPoller

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let error = poller.lastError {
                errorRow(error)
            } else if poller.sessions.isEmpty {
                emptyRow
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(poller.byProject, id: \.project) { group in
                            ProjectSection(group: group)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
            }

            Divider()
            footer
        }
        .frame(width: 340)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Image(systemName: "ant.fill")
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
            Button { poller.pollNow() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(10)
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
    let group: (project: String, name: String, sessions: [AgentSession])

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
