import SwiftUI

struct MenuContentView: View {
    @ObservedObject var poller: AgentPoller
    @AppStorage("menuBarIcon") private var iconRaw = MenuBarIcon.robot.rawValue

    private var icon: MenuBarIcon { MenuBarIcon(rawValue: iconRaw) ?? .robot }

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
        HStack {
            if let updated = poller.lastUpdated {
                Text("Updated \(updated, style: .time)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
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

    var body: some View {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
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
