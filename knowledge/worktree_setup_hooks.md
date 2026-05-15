---
name: Worktree Setup Hooks
description: How worktree build prep is triggered — git post-checkout hook (preferred) vs Claude SessionStart hook, plus failed approaches and key technical details
type: project
---

## Preferred Approach: git post-checkout hook

Use a `post-checkout` hook in `.git/hooks/post-checkout` to detect new worktree creation. When the first arg is the null hash (`0000000000000000000000000000000000000000`), it's a fresh worktree (not a branch switch). Run setup logic (e.g. `bin/prep-worktree`) there.

**Why:** Native git mechanism — works for `claude -w`, manual `git worktree add`, any tool. No Claude-specific workarounds needed.

**How to apply:** Put worktree setup in `post-checkout`, gated on the null hash check. Per-repo setup scripts (like `bin/prep-worktree`) can still hold repo-specific logic.

Source: https://mskelton.dev/bytes/using-git-hooks-when-creating-worktrees

## Previous Approach: Claude SessionStart hook

Previously used a global `SessionStart` hook in `~/.claude/settings.json` that ran `bin/prep-worktree .` if in a worktree and the script exists. This worked but was Claude-specific.

## PodHaven-specific: Xcode build optimization

`bin/prep-worktree` does three things for PodHaven worktrees:
1. **SourcePackages symlink** — pre-creates DerivedData folder with SourcePackages symlinked to main repo's, skipping package fetching
2. **Compilation caching** — copies `CompilationCachingSetting = Enable` from main repo's xcuserdata (per-user, gitignored)
3. **Background xcodebuild** — kicks off `xcodebuild build -quiet` in background to warm caches

## Failed Approaches

- **DerivedData symlink between hashes** — Xcode embeds absolute source paths; sharing DerivedData across paths causes full rebuilds
- **Stable symlink path** — Xcode resolves symlinks before computing DerivedData hash
- **WorkspaceSettings in xcshareddata** — Xcode reverts shared DerivedData/caching settings; strictly per-user
- **`WorktreeCreate` hook** — Replaces default `git worktree` behavior (expects hook to create worktree and print path on stdout), not for running scripts alongside
- **`PostToolUse` with `EnterWorktree`** — Doesn't fire for `claude -w` (worktree created at startup before session)
- **Project-level `SessionStart` hook** — Worktrees get committed version, so changes require a commit first

## Key Technical Details

- **Xcode DerivedData hash**: MD5 of xcodeproj path → two uint64 (big-endian) → each as 14 base-26 lowercase letters = 28 char hash
- **Compilation cache**: `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex/` — shared across all projects, content-addressed
- **`claude -w` file deletion bug**: Worktrees via `claude -w` sometimes have hundreds of tracked files deleted. Manual `git worktree add` doesn't. Root cause unknown.
- **Stale worktrees cause hangs**: If a previous worktree at the same name wasn't cleaned up, `claude -w` hangs. Fix: `git worktree prune && git branch -d <branch>`
