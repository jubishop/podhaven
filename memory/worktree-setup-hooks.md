---
name: worktree-setup-hooks
description: "Past worktree cache failures, stale SwiftPM artifact paths, and approaches that broke Xcode builds."
type: reference
---

# Worktree cache lessons

Use the [development workflow](../docs/development-workflow.md) for maintained setup and automatic cleanup instructions. These historical failure reports explain the checks that preparation must preserve; re-verify tool-specific claims before relying on them.

## Stale SwiftPM artifact paths

When cleanup deletes a removed worktree's DerivedData, the shared clone's `workspace-state.json` may still record Sentry xcframework paths through that deleted DerivedData. Every remaining worktree then fails with `error: There is no XCFramework found at '~/Library/Developer/Xcode/DerivedData/PodHaven-<hash>/SourcePackages/artifacts/sentry-cocoa/Sentry/Sentry.xcframework'` even though the artifacts still exist under `~/Library/Developer/SharedSourcePackages/PodHaven/artifacts/`.

Fix: rewrite the stale prefix in `~/Library/Developer/SharedSourcePackages/PodHaven/workspace-state.json` to point at the shared clone itself:

```sh
sed -i '' "s|<stale DerivedData path>/SourcePackages|$HOME/Library/Developer/SharedSourcePackages/PodHaven|g" workspace-state.json
```

`xcodebuild -resolvePackageDependencies` does not fix it — resolution succeeds but never re-checks artifact paths. This can recur whenever SwiftPM re-resolves from a worktree that is later removed.

After rewriting `workspace-state.json`, validate it with `jq empty`; `plutil -lint`
was not a reliable JSON check for this file on this machine. To prove the
repair without repeating release side effects, use a warning-free
`xcodebuild build-for-testing` or archive-only run with
`-hideShellScriptEnvironment`, and confirm that Xcode copies and signs the
Sentry framework. Run the full deploy only when the release path itself must
be exercised because it can create tag and upload side effects.

Related symptom at the same time: "Provisioning profile … doesn't include signing certificate" — a stale iOS Team Provisioning Profile; one build with `xcodebuild -allowProvisioningUpdates` regenerates it.

## Failed Approaches

- **DerivedData symlink between hashes** — Xcode embeds absolute source paths; sharing DerivedData across paths causes full rebuilds
- **Stable symlink path** — Xcode resolves symlinks before computing DerivedData hash
- **SourcePackages symlink into main's DerivedData** — link target vanishes whenever main's DerivedData is cleaned, so worktrees silently fall back to fresh full copies; replaced by a shared clone path outside DerivedData
- **Background warm `xcodebuild` on worktree creation** — a second build on the same DerivedData hard-fails (`exit 65`, `build.db database is locked`), so if an agent builds within ~80s of creation its build dies, not the warm one. Couldn't be serialized without the build going through a wrapper the agent must opt into. Measured payoff was small anyway: fresh-worktree build ~73–84s, and the global content-addressed compilation cache only shaved ~11s across a new DerivedData path (absolute paths bust most cache keys). Dropped; the agent's first build is the warming pass.
- **Review-specific DerivedData under `/tmp` for runtime tests** — a confirmed
  PodHaven run compiled but XCTest bootstrap was blocked by
  AppleSystemPolicy/Gatekeeper. Use standard Xcode DerivedData for runtime
  tests unless isolation is necessary, and inspect the result for bootstrap
  errors instead of treating compilation as proof that tests ran.
- **WorkspaceSettings in xcshareddata** — Xcode reverts shared DerivedData/caching settings; strictly per-user
- **`WorktreeCreate` hook** — Replaces default `git worktree` behavior (expects hook to create worktree and print path on stdout), not for running scripts alongside
- **`PostToolUse` with `EnterWorktree`** — Doesn't fire for `claude -w` (worktree created at startup before session)
- **Project-level `SessionStart` hook** — Worktrees get committed version, so changes require a commit first

## Key Technical Details

- **Xcode DerivedData hash**: MD5 of xcodeproj path → two uint64 (big-endian) → each as 14 base-26 lowercase letters = 28 char hash
- **Compilation cache**: `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex/` — shared across all projects, content-addressed
- **Historical `claude -w` file deletion report**: Worktrees via `claude -w` sometimes have hundreds of tracked files deleted. Manual `git worktree add` doesn't. Root cause unknown.
- **Stale worktrees cause hangs**: If a previous worktree at the same name wasn't cleaned up, `claude -w` hangs. Fix: `git worktree prune && git branch -d <branch>`
