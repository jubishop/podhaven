#!/bin/bash
# Pre-creates a DerivedData symlink so worktrees share the main repo's warm build cache.
# Called by SessionStart hook — detects if we're in a worktree and links if so.

set -eo pipefail

LOG="/tmp/link-deriveddata.log"
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

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
" "$1" < /dev/null
}

WORKTREE_PATH="$(pwd)"
MAIN_REPO="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"

log "main=$MAIN_REPO worktree=$WORKTREE_PATH"

# Skip if not in a worktree
if [ "$MAIN_REPO" = "$WORKTREE_PATH" ]; then
  log "SKIP: not a worktree"
  exit 0
fi

MAIN_HASH=$(xcode_hash "$MAIN_REPO/$PROJECT_NAME.xcodeproj")
MAIN_DD="$DERIVED_DATA_DIR/$PROJECT_NAME-$MAIN_HASH"

WT_HASH=$(xcode_hash "$WORKTREE_PATH/$PROJECT_NAME.xcodeproj")
WT_DD="$DERIVED_DATA_DIR/$PROJECT_NAME-$WT_HASH"

if [ -d "$MAIN_DD" ] && [ ! -e "$WT_DD" ]; then
  ln -s "$MAIN_DD" "$WT_DD"
  log "LINKED: $WT_DD -> $MAIN_DD"
elif [ -L "$WT_DD" ]; then
  log "SKIP: symlink already exists"
elif [ ! -d "$MAIN_DD" ]; then
  log "WARN: main DerivedData not found — build in Xcode from main first"
fi
