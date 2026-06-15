#!/bin/bash
# List and download event attachments via `sentry api`.
#
# Usage:
#   download_event_attachments.sh --event EVENT_ID --dir DIR [--name FILE ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

EVENT_ID=""
DIR=""
NAMES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      EVENT_ID="$2"
      shift 2
      ;;
    --dir)
      DIR="$2"
      shift 2
      ;;
    --name)
      NAMES+=("$2")
      shift 2
      ;;
    -h | --help)
      sed -n '1,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$EVENT_ID" || -z "$DIR" ]]; then
  echo "Usage: download_event_attachments.sh --event EVENT_ID --dir DIR [--name FILE ...]" >&2
  exit 1
fi

require_sentry_auth
mkdir -p "$DIR"

LIST_JSON="$(mktemp)"
trap 'rm -f "$LIST_JSON"' EXIT

sentry_cmd api "projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/${EVENT_ID}/attachments/" --json \
  > "$LIST_JSON"

python3 - "$LIST_JSON" "$EVENT_ID" "${NAMES[@]}" <<'PY'
import json
import sys

attachments = json.loads(open(sys.argv[1]).read())
event_id = sys.argv[2]
wanted = set(sys.argv[3:])
print(f"Event {event_id}: {len(attachments)} attachment(s)")
for row in attachments:
    size = row.get("size")
    size_text = f"{size} bytes" if size is not None else "unknown size"
    print(f"  - {row['id']}  {row['name']}  ({size_text})")
selected = attachments
if wanted:
    selected = [row for row in attachments if row["name"] in wanted]
    missing = wanted - {row["name"] for row in selected}
    for name in sorted(missing):
        print(f"Warning: attachment not found: {name}", file=sys.stderr)
if not selected:
    raise SystemExit(f"Error: no attachments to download for event {event_id}")
PY

while IFS=$'\t' read -r ATTACHMENT_ID FILENAME; do
  [[ -z "$ATTACHMENT_ID" ]] && continue
  TARGET="${DIR}/${FILENAME}"
  sentry_cmd api \
    "projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/${EVENT_ID}/attachments/${ATTACHMENT_ID}/?download=1" \
    > "$TARGET"
  echo "Downloaded ${FILENAME} -> ${TARGET}"
done < <(
  python3 - "$LIST_JSON" "${NAMES[@]}" <<'PY'
import json
import sys

attachments = json.loads(open(sys.argv[1]).read())
wanted = set(sys.argv[2:])
selected = attachments
if wanted:
    selected = [row for row in attachments if row["name"] in wanted]
for row in selected:
    print(f"{row['id']}\t{row['name']}")
PY
)
