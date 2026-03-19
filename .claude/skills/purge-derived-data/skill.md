---
description: Delete stale worktree DerivedData folders, keeping only the main repo's build cache
allowed-tools: Bash(rm:*), Bash(du:*), Bash(ls:*), Bash(cat:*), Bash(grep:*)
disable-model-invocation: true
---

Purge all PodHaven DerivedData folders in `~/Library/Developer/Xcode/DerivedData/` except the main repo's.

## Step 1 — Identify the main repo's DerivedData

The main repo's xcodeproj path is `/Users/jubi/Desktop/podhaven/PodHaven.xcodeproj`. Find its DerivedData folder by checking `info.plist` in each `~/Library/Developer/Xcode/DerivedData/PodHaven-*/` directory for a `WorkspacePath` matching this path.

## Step 2 — List stale folders with sizes

For every `PodHaven-*` folder that does NOT match the main repo, show:
- Folder name
- Size (via `du -sh`)
- The `WorkspacePath` it was built from (if available in `info.plist`)

Also show the total size that will be reclaimed.

If there are no stale folders, report that and stop.

## Step 3 — Delete

Delete all the stale folders identified in Step 2. Report how much space was freed.
