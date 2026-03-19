#!/bin/bash
# Pre-creates a DerivedData symlink so worktrees share the main repo's warm build cache.
# Called by the WorktreeCreate hook.

set -euo pipefail

DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"
PROJECT_NAME="PodHaven"

xcode_hash() {
  python3 -c "
import hashlib, struct, sys
md5 = hashlib.md5(sys.argv[1].encode('utf-8')).digest()
hi, lo = struct.unpack('>QQ', md5)
r = [''] * 28
v = hi
for i in range(13, -1, -1):
    r[i] = chr(ord('a') + v % 26); v //= 26
v = lo
for i in range(27, 13, -1):
    r[i] = chr(ord('a') + v % 26); v //= 26
print(''.join(r))
" "$1"
}

MAIN_REPO="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
MAIN_HASH=$(xcode_hash "$MAIN_REPO/$PROJECT_NAME.xcodeproj")
MAIN_DD="$DERIVED_DATA_DIR/$PROJECT_NAME-$MAIN_HASH"

WORKTREE_PATH="$(pwd)"
WT_HASH=$(xcode_hash "$WORKTREE_PATH/$PROJECT_NAME.xcodeproj")
WT_DD="$DERIVED_DATA_DIR/$PROJECT_NAME-$WT_HASH"

if [ -d "$MAIN_DD" ] && [ ! -e "$WT_DD" ]; then
  ln -s "$MAIN_DD" "$WT_DD"
  echo "Linked worktree DerivedData → main repo's build cache"
elif [ -L "$WT_DD" ]; then
  echo "DerivedData symlink already exists"
elif [ ! -d "$MAIN_DD" ]; then
  echo "Warning: main repo DerivedData not found at $MAIN_DD — build in Xcode from main first"
fi
