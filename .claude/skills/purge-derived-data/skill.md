---
description: Delete stale worktree DerivedData folders and optionally clear the compilation cache
allowed-tools: Bash(rm:*), Bash(du:*), Bash(ls:*), Bash(cat:*), Bash(grep:*), Bash(python3:*)
disable-model-invocation: true
---

Purge stale PodHaven DerivedData and check the compilation cache size.

## Step 1 — Identify the main repo's DerivedData

Compute the main repo's DerivedData hash using this algorithm:

```bash
python3 -c "
import hashlib, struct
md5 = hashlib.md5('/Users/jubi/Desktop/podhaven/PodHaven.xcodeproj'.encode('utf-8')).digest()
hi, lo = struct.unpack('>QQ', md5)
r = [''] * 28
v = hi
for i in range(13, -1, -1):
    r[i] = chr(ord('a') + v % 26); v //= 26
v = lo
for i in range(27, 13, -1):
    r[i] = chr(ord('a') + v % 26); v //= 26
print(''.join(r))
"
```

The main repo's DerivedData folder is `~/Library/Developer/Xcode/DerivedData/PodHaven-<hash>`.

## Step 2 — List stale DerivedData folders

For every `PodHaven-*` folder in `~/Library/Developer/Xcode/DerivedData/` that is NOT the main repo's (by hash), show:
- Folder name (and whether it's a symlink)
- Size (via `du -sh`)
- The `WorkspacePath` from its `info.plist` (if available)

Also show the total size that will be reclaimed.

If there are no stale folders, report "No stale DerivedData folders found."

## Step 3 — Delete stale DerivedData

Delete all stale folders (and symlinks) identified in Step 2. Report how much space was freed.

## Step 4 — Check compilation cache

Check the size of `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex/`.

- If over 10 GB, warn the user and offer to delete it: "Compilation cache is X GB. Delete it to free space? (You'll need to rebuild once to repopulate it.)"
- If under 10 GB, just report the size.

Only delete the compilation cache if the user confirms.
