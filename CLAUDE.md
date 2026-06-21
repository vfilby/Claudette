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

## `master` is protected — everything lands via a squash-merged PR

`master` is guarded by a branch ruleset: no direct pushes, linear history
required, and the CI check **`Build (ad-hoc signed)`** must pass before merge.
**Squash is the only allowed merge method** (merge commits and rebase merges are
disabled at the repo level), so every feature reaches `master` as a single
commit through a pull request — never via `git merge` + push.

## Worktrees — a feature is NOT done until its PR is merged to `master`

Features are developed in git worktrees under `.claude/worktrees/`. A worktree is
**only complete once its work is committed, pushed, and its PR is squash-merged
into `master`** — and then the worktree and its branch are removed. Leaving work
sitting uncommitted or on an unmerged branch is how features get silently lost
when the next one starts.

Closing out a worktree feature, every time:

```sh
# 1. In the worktree: commit everything (including new untracked files)
git -C .claude/worktrees/<name> add -A
git -C .claude/worktrees/<name> commit -m "feat: <summary>"

# 2. Push the branch and open a PR
git -C .claude/worktrees/<name> push -u origin worktree-<name>
gh pr create --fill --head worktree-<name> --base master

# 3. Enable auto-merge (squash). It merges once `Build (ad-hoc signed)` is green.
gh pr merge --auto --squash <pr-number>

# 4. After the PR merges: sync master, rebuild + relaunch (see above), confirm

# 5. Collapse: remove the now-merged worktree and delete its branch
git worktree remove .claude/worktrees/<name>
git branch -d worktree-<name>
```

Do not start a new feature/worktree while a finished one is still unmerged.
