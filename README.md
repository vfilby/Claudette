# Claudette

[![CI](https://github.com/vfilby/Claudette/actions/workflows/ci.yml/badge.svg)](https://github.com/vfilby/Claudette/actions/workflows/ci.yml)

A macOS menu bar app that tracks actively-running **Claude Code** background sessions,
grouped by project folder and by category (Working / Needs input / Completed / Failed),
with native notifications when a session finishes or needs your attention.


> [!IMPORTANT]
> Claudette relies on Claude Code's **Agent View** preview feature, which exposes the
> `claude agents` command it polls. You must have Agent View enabled in Claude Code for
> Claudette to detect any sessions — without it, the menu bar will always read empty.

<img width="386" height="603" alt="image" src="https://github.com/user-attachments/assets/ced952fe-3d38-4fd3-ba7e-12cf92bc2d57" />


## Download

Grab the latest signed & notarized build from the
[**Releases**](https://github.com/vfilby/Claudette/releases) page (`.dmg` or `.zip`).
Builds are signed with a Developer ID and notarized by Apple, so they open without
Gatekeeper warnings. Releasing is automated — see
[`.github/RELEASE_SETUP.md`](.github/RELEASE_SETUP.md).

## How it works

Claudette polls `claude agents --json` on an interval and parses the live session list.
It rolls worktree sessions (`<project>/.claude/worktrees/...`) back up under their parent
project, sorts attention-needing sessions to the top, and fires a `UserNotifications`
alert whenever a session transitions to **needs input**, **finished**, or **failed**.

It can monitor the **local Mac and remote hosts over SSH** at the same time — see
[Remote hosts](#remote-hosts) below.

Data source reference (verified against Claude Code 2.1.179):
- `claude agents --json` — active sessions: `id, sessionId, cwd, name, kind, startedAt, state, status, pid`
- `claude agents --json --all` — includes completed (drops `status`/`pid`)
- `~/.claude/daemon/roster.json` — richer daemon state incl. dispatched agent type (unofficial)

## Build & run

Requires [XcodeGen](https://github.com/yonez2k/XcodeGen) (`brew install xcodegen`) and Xcode.

```sh
xcodegen generate          # creates Claudette.xcodeproj from project.yml
xcodebuild -project Claudette.xcodeproj -scheme Claudette -configuration Release build
open build/Claudette.app
```

Or just open `Claudette.xcodeproj` in Xcode and hit Run.

The app is ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`), so no Apple Developer team is
needed to build and run it locally. On first launch, approve the notification prompt.

It runs as a menu bar accessory (`LSUIElement`) — no Dock icon. The menu bar glyph shows
a count of working + needs-input sessions; click it for the grouped breakdown.

## Remote hosts

Claudette can poll Claude Code sessions running on other machines over **key-based,
passwordless SSH**. Click the **server icon** in the footer to open *Remote hosts*, then
**Add remote host** and fill in:

| Field | Notes |
|-------|-------|
| **Label** | Optional display name; defaults to `user@host`. |
| **User** / **Host** | The SSH target (`user@hostname`). |
| **Port** | Defaults to `22`. |
| **Key file** | Optional explicit identity file, e.g. `~/.ssh/id_ed25519`. Leave blank to use your SSH defaults / agent. |
| **Claude path** | Optional. Leave blank and Claudette resolves `claude` through a remote login shell (`bash -lc`). Set it explicitly if `claude` isn't on the remote login PATH. |

Use the **⚡️ test button** on each host to verify connectivity before relying on it.
Remote sessions appear under a per-host header and their notifications are tagged with
the host label.

### How it polls

For each enabled host Claudette runs:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    [-p PORT] [-i KEYFILE] user@host 'bash -lc "claude agents --json"'
```

- `BatchMode=yes` means it **never prompts for a password** — set up an SSH key first
  (`ssh-copy-id user@host`). Password-only hosts will fail fast rather than hang. For a
  smoother experience, use an `ssh-agent` or `ControlMaster` so auth happens once.
- `ConnectTimeout` keeps a dead host from stalling the menu; hosts are polled in parallel.
- `accept-new` trusts a new host key on first connect and pins it thereafter.

Hosts are stored in `UserDefaults` (`com.vfilby.Claudette.hosts`). The local Mac is always
monitored and can't be removed.

## Opening a session

Click any session row — or click the notification it fired — to open Claude Code's
interactive **agent view** (`claude agents --cwd <project>`) in a terminal, filtered to
that session's project. Background agents are daemon workers with no foreground TTY, so
there's no pane to "switch" to and `claude --resume <id>` refuses them; the agent view is
the canonical place to read output and reattach (`SessionLauncher.swift`).

The terminal is selectable from the window picker (the `macwindow` button in the footer):
Ghostty, iTerm, Terminal, kitty, WezTerm, Alacritty are launched directly; **Automatic**
picks the first installed; **System default** writes an executable `.command` file and
lets the OS open it, so any other terminal works as your default handler.

## Customizing

- **Poll interval** — `AgentPoller.pollInterval` (default 4s).
- **Which transitions notify** — `AgentPoller.detectTransitions`.
- **Terminal to open sessions in** — the footer picker, persisted as the `terminalApp`
  default; add a new terminal by giving it a `bundleID` + launch strategy in `TerminalApp`.
- **Binary location** — `AgentPoller.resolveClaudeBinary` checks `~/.local/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin`, `~/.claude/local`, then a login shell.
- **SSH options** — `AgentPoller.sshArguments` (timeout, host-key policy, identity).

## Ideas / next steps

- Launch at login (`SMAppService`).
- Click a session to `claude attach <id>` in a new terminal (`ssh -t` for remotes).
- Read `roster.json` directly to group by agent type, and avoid spawning the CLI.
- Per-project mute, and a "needs input" sound distinct from "finished".
- Edit existing remote hosts in place (currently delete + re-add).
