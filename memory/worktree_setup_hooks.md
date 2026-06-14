---
name: worktree-setup-hooks
description: How worktree build prep is triggered — git post-checkout hook (preferred) vs Claude SessionStart hook, PodHaven prep-worktree details, stale SPM artifact-path recovery, and failed approaches
type: project
status: active
---

## Preferred Approach: git post-checkout hook

Use a `post-checkout` hook in `.git/hooks/post-checkout` to detect new worktree creation. When the first arg is the null hash (`0000000000000000000000000000000000000000`), it's a fresh worktree (not a branch switch). Run setup logic (e.g. `bin/prep-worktree`) there. PodHaven's hook prefers the common repo's `bin/prep-worktree` and passes the new worktree path into it.

**Why:** Native git mechanism — works for `claude -w`, manual `git worktree add`, any tool. No Claude-specific workarounds needed.

**How to apply:** Put worktree setup in `post-checkout`, gated on the null hash check. Per-repo setup scripts (like `bin/prep-worktree`) can still hold repo-specific logic.

Source: https://mskelton.dev/bytes/using-git-hooks-when-creating-worktrees

## Previous Approach: Claude SessionStart hook

Previously used a global `SessionStart` hook in `~/.claude/settings.json` that ran `bin/prep-worktree .` if in a worktree and the script exists. This worked but was Claude-specific.

## PodHaven-specific: Xcode build optimization

`bin/prep-worktree` does four things for PodHaven worktrees:
1. **direnv approval** — runs `direnv allow` when the worktree `.envrc` matches the main repo's `.envrc`; divergent `.envrc` files stay blocked for manual review
2. **SourcePackages sharing** — keeps one SwiftPM clone at a stable path outside DerivedData (`~/Library/Developer/SharedSourcePackages/<project>`), seeded from main's (or the worktree's) existing checkouts. Each worktree's and main's `<DerivedData>/SourcePackages` is symlinked there; the IDE and any `xcodebuild` reach the clone through that default-location symlink, so a DerivedData wipe only drops the symlink, never the checkouts.
3. **Compilation caching** — copies `CompilationCachingSetting = Enable` from main repo's xcuserdata (per-user, gitignored)
4. **Orphan DerivedData GC** — deletes `PodHaven-*` DerivedData folders whose `info.plist` `WorkspacePath` no longer exists (i.e. removed worktrees)

Teardown deliberately stays out of the generic `ghdw`/`git worktree remove` path: git has no worktree-removal hook, so orphaned DerivedData is garbage-collected on the next worktree creation (step 4) instead, regardless of how the old worktree was removed.

### Stale SPM artifact paths (orphan GC side effect)

When step 4 deletes a removed worktree's DerivedData, the shared clone's `workspace-state.json` may still record Sentry xcframework paths through that deleted DerivedData. Every remaining worktree then fails with `error: There is no XCFramework found at '~/Library/Developer/Xcode/DerivedData/PodHaven-<hash>/SourcePackages/artifacts/sentry-cocoa/Sentry/Sentry.xcframework'` even though the artifacts still exist under `~/Library/Developer/SharedSourcePackages/PodHaven/artifacts/`.

Fix: rewrite the stale prefix in `~/Library/Developer/SharedSourcePackages/PodHaven/workspace-state.json` to point at the shared clone itself:

```sh
sed -i '' "s|<stale DerivedData path>/SourcePackages|$HOME/Library/Developer/SharedSourcePackages/PodHaven|g" workspace-state.json
```

`xcodebuild -resolvePackageDependencies` does not fix it — resolution succeeds but never re-checks artifact paths. This can recur whenever SwiftPM re-resolves from a worktree that is later removed.

Related symptom at the same time: "Provisioning profile … doesn't include signing certificate" — a stale iOS Team Provisioning Profile; one build with `xcodebuild -allowProvisioningUpdates` regenerates it.

## Failed Approaches

- **DerivedData symlink between hashes** — Xcode embeds absolute source paths; sharing DerivedData across paths causes full rebuilds
- **Stable symlink path** — Xcode resolves symlinks before computing DerivedData hash
- **SourcePackages symlink into main's DerivedData** — link target vanishes whenever main's DerivedData is cleaned, so worktrees silently fall back to fresh full copies; replaced by a shared clone path outside DerivedData
- **Background warm `xcodebuild` on worktree creation** — a second build on the same DerivedData hard-fails (`exit 65`, `build.db database is locked`), so if an agent builds within ~80s of creation its build dies, not the warm one. Couldn't be serialized without the build going through a wrapper the agent must opt into. Measured payoff was small anyway: fresh-worktree build ~73–84s, and the global content-addressed compilation cache only shaved ~11s across a new DerivedData path (absolute paths bust most cache keys). Dropped; the agent's first build is the warming pass.
- **WorkspaceSettings in xcshareddata** — Xcode reverts shared DerivedData/caching settings; strictly per-user
- **`WorktreeCreate` hook** — Replaces default `git worktree` behavior (expects hook to create worktree and print path on stdout), not for running scripts alongside
- **`PostToolUse` with `EnterWorktree`** — Doesn't fire for `claude -w` (worktree created at startup before session)
- **Project-level `SessionStart` hook** — Worktrees get committed version, so changes require a commit first

## Key Technical Details

- **Xcode DerivedData hash**: MD5 of xcodeproj path → two uint64 (big-endian) → each as 14 base-26 lowercase letters = 28 char hash
- **Compilation cache**: `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex/` — shared across all projects, content-addressed
- **`claude -w` file deletion bug**: Worktrees via `claude -w` sometimes have hundreds of tracked files deleted. Manual `git worktree add` doesn't. Root cause unknown.
- **Stale worktrees cause hangs**: If a previous worktree at the same name wasn't cleaned up, `claude -w` hangs. Fix: `git worktree prune && git branch -d <branch>`
