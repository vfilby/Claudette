# Claudette — working agreement

macOS menu bar app that tracks running Claude Code sessions. Built with SwiftUI,
generated from `project.yml` via XcodeGen.

## Build & run (do this after EVERY completed feature)

The trunk branch is `master`. When a feature is finished, you must rebuild and
relaunch so the change is actually running — don't make the user ask:

```sh
xcodegen generate                                            # regenerate the .xcodeproj from project.yml
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Claudette.xcodeproj -scheme Claudette -configuration Release build
pkill -x Claudette                                           # stop the running instance
open build/Claudette.app                                     # relaunch the fresh build
```

Notes:
- `xcodebuild` needs full Xcode, not Command Line Tools — hence `DEVELOPER_DIR`.
- `Sources/` is globbed by `project.yml`, so new `.swift` files are picked up on
  `xcodegen generate`; no manual project edits needed.
- `.xcodeproj`, `build/`, and `DerivedData/` are gitignored — never commit them.

## Worktrees — a feature is NOT done until it's merged back to `master`

Features are developed in git worktrees under `.claude/worktrees/`. A worktree is
**only complete once its work is committed AND merged back into `master`** — and
then the worktree and its branch are removed. Leaving work sitting uncommitted or
on an unmerged branch is how features get silently lost when the next one starts.

Closing out a worktree feature, every time:

```sh
# 1. In the worktree: commit everything (including new untracked files)
git -C .claude/worktrees/<name> add -A
git -C .claude/worktrees/<name> commit -m "feat: <summary>"

# 2. From the main checkout on master: merge it in and resolve conflicts
git checkout master
git merge worktree-<name>

# 3. Rebuild + relaunch (see above), confirm it works

# 4. Collapse: remove the now-merged worktree and delete its branch
git worktree remove .claude/worktrees/<name>
git branch -d worktree-<name>
```

Do not start a new feature/worktree while a finished one is still unmerged.
