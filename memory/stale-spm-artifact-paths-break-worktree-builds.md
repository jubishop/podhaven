---
name: stale-spm-artifact-paths-break-worktree-builds
description: Shared SourcePackages workspace-state.json stores absolute artifact paths into whichever DerivedData resolved them; pruning that worktree's DerivedData breaks every build with "There is no XCFramework found" for Sentry.
type: reference
---

# Stale SwiftPM artifact paths break worktree builds

Symptom: `xcodebuild` fails in any worktree with `error: There is no XCFramework
found at '~/Library/Developer/Xcode/DerivedData/PodHaven-<hash>/SourcePackages/
artifacts/sentry-cocoa/Sentry/Sentry.xcframework'` where that DerivedData folder
does not exist.

Cause: all worktrees share one SwiftPM clone at
`~/Library/Developer/SharedSourcePackages/PodHaven` (symlinked into each
DerivedData by `bin/prep-worktree`). Its `workspace-state.json` records binary
artifacts (Sentry xcframeworks) by **absolute path through whichever
DerivedData performed the resolution**. When that worktree is removed,
`prep-worktree`'s `prune_orphan_derived_data` deletes its DerivedData and the
recorded paths dangle — even though the artifacts still exist in the shared
clone's own `artifacts/` directory.

Fix: rewrite the stale prefix in
`~/Library/Developer/SharedSourcePackages/PodHaven/workspace-state.json` to
point at the shared clone itself:

```sh
sed -i '' "s|<stale DerivedData path>/SourcePackages|$HOME/Library/Developer/SharedSourcePackages/PodHaven|g" workspace-state.json
```

`xcodebuild -resolvePackageDependencies` does NOT fix it (resolution succeeds;
it never re-checks the artifact paths). This can recur whenever SwiftPM
re-resolves from some worktree and then that worktree is removed.

Related symptom seen at the same time: "Provisioning profile … doesn't include
signing certificate" — a stale iOS Team Provisioning Profile; one build with
`xcodebuild -allowProvisioningUpdates` regenerates it.
