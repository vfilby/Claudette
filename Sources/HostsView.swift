import SwiftUI

/// The "Manage remote hosts" screen: lists configured SSH remotes (toggle / test /
/// delete) and provides a form to add new ones. Reached from the footer's server
/// button. Uses key-based, passwordless SSH only.
struct HostsView: View {
    @ObservedObject var poller: AgentPoller
    @ObservedObject var hosts: HostStore
    let onClose: () -> Void

    @State private var draft = Host.newRemote()
    @State private var adding = false
    /// Per-host test outcome, keyed by `Host.id`.
    @State private var testResults: [String: TestState] = [:]

    enum TestState: Equatable {
        case running
        case ok(Int)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hosts.remotes.isEmpty {
                        Text("No remote hosts yet. Add one below to monitor Claude Code sessions on another machine over SSH.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    } else {
                        ForEach(hosts.remotes) { host in
                            HostRow(host: host,
                                    test: testResults[host.id],
                                    onToggle: { hosts.setEnabled(host, $0) },
                                    onTest: { runTest(host) },
                                    onDelete: { hosts.remove(host); testResults[host.id] = nil })
                            Divider().padding(.leading, 12)
                        }
                    }

                    if adding {
                        addForm
                    } else {
                        Button {
                            draft = Host.newRemote()
                            adding = true
                        } label: {
                            Label("Add remote host", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 460)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button { onClose() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Back to sessions")
            Image(systemName: "server.rack")
            Text("Remote hosts").font(.headline)
            Spacer()
        }
        .padding(10)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New SSH host").font(.subheadline.weight(.semibold))
            field("Label", text: $draft.label, placeholder: "Optional display name")
            field("User", text: $draft.user, placeholder: "e.g. vfilby")
            field("Host", text: $draft.hostname, placeholder: "hostname or IP")
            HStack(spacing: 6) {
                Text("Port").frame(width: 64, alignment: .leading).font(.caption)
                TextField("22", value: $draft.port, format: .number)
                    .textFieldStyle(.roundedBorder)
            }
            field("Key file", text: $draft.identityFile, placeholder: "~/.ssh/id_ed25519 (optional)")
            field("Claude path", text: $draft.remoteClaudePath, placeholder: "remote claude path (optional)")

            HStack {
                Spacer()
                Button("Cancel") { adding = false }
                    .buttonStyle(.borderless)
                Button("Add") {
                    hosts.add(draft)
                    adding = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.hostname.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text(label).frame(width: 64, alignment: .leading).font(.caption)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Actions

    private func runTest(_ host: Host) {
        testResults[host.id] = .running
        poller.test(host) { result in
            switch result {
            case .success(let count): testResults[host.id] = .ok(count)
            case .failure(let error): testResults[host.id] = .failed(error.message)
            }
        }
    }
}

// MARK: - Host row

private struct HostRow: View {
    let host: Host
    let test: HostsView.TestState?
    let onToggle: (Bool) -> Void
    let onTest: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { host.enabled }, set: onToggle))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.displayLabel).font(.callout.weight(.medium))
                    Text(host.connectionSummary).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onTest() } label: { Image(systemName: "bolt.horizontal.circle") }
                    .buttonStyle(.borderless)
                    .help("Test connection")
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove host")
            }

            if let test {
                testRow(test)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func testRow(_ state: HostsView.TestState) -> some View {
        switch state {
        case .running:
            Label("Testing…", systemImage: "hourglass")
                .font(.caption2).foregroundStyle(.secondary)
        case .ok(let count):
            Label("Connected · \(count) session\(count == 1 ? "" : "s")",
                  systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption2).foregroundStyle(.red)
        }
    }
}
