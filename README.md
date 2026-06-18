# Claudette

A macOS menu bar app that tracks actively-running **Claude Code** background sessions,
grouped by project folder and by category (Working / Needs input / Completed / Failed),
with native notifications when a session finishes or needs your attention.

## How it works

Claudette polls `claude agents --json` on an interval and parses the live session list.
It rolls worktree sessions (`<project>/.claude/worktrees/...`) back up under their parent
project, sorts attention-needing sessions to the top, and fires a `UserNotifications`
alert whenever a session transitions to **needs input**, **finished**, or **failed**.

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

## Ideas / next steps

- Launch at login (`SMAppService`).
- Read `roster.json` directly to group by agent type, and avoid spawning the CLI.
- Per-project mute, and a "needs input" sound distinct from "finished".
