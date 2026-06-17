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

## Customizing

- **Poll interval** — `AgentPoller.pollInterval` (default 4s).
- **Which transitions notify** — `AgentPoller.detectTransitions`.
- **Binary location** — `AgentPoller.resolveClaudeBinary` checks `~/.local/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin`, `~/.claude/local`, then a login shell.

## Ideas / next steps

- Launch at login (`SMAppService`).
- Click a session to `claude attach <id>` in a new terminal.
- Read `roster.json` directly to group by agent type, and avoid spawning the CLI.
- Per-project mute, and a "needs input" sound distinct from "finished".
