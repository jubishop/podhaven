#!/bin/bash
# List and download event attachments via `sentry api`.
#
# Usage:
#   download_event_attachments.sh --event EVENT_ID --issue-json FILE
#     [--dir DIR (--name FILE ... | --all)]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

EVENT_ID=""
ISSUE_JSON=""
DIR=""
NAMES=()
DOWNLOAD_ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      EVENT_ID="$2"
      shift 2
      ;;
    --issue-json)
      ISSUE_JSON="$2"
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
    --all)
      DOWNLOAD_ALL=1
      shift
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

if [[ -z "$EVENT_ID" || -z "$ISSUE_JSON" ]]; then
  echo "Usage: download_event_attachments.sh --event EVENT_ID --issue-json FILE [--dir DIR (--name FILE ... | --all)]" >&2
  exit 1
fi
if [[ ! "$EVENT_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Error: unsafe event ID: $EVENT_ID" >&2
  exit 1
fi
if [[ ! -f "$ISSUE_JSON" ]]; then
  echo "Error: issue JSON not found: $ISSUE_JSON" >&2
  exit 1
fi
if [[ "$DOWNLOAD_ALL" == "1" && "${#NAMES[@]}" -gt 0 ]]; then
  echo "Error: use either --all or --name, not both." >&2
  exit 1
fi
if [[ "$DOWNLOAD_ALL" == "1" || "${#NAMES[@]}" -gt 0 ]] && [[ -z "$DIR" ]]; then
  echo "Error: --dir is required when downloading attachments." >&2
  exit 1
fi

require_sentry_auth

IFS=$'\t' read -r ISSUE_ORG ISSUE_PROJECT < <(
  python3 - "$ISSUE_JSON" <<'PY'
import json
import sys

issue = json.load(open(sys.argv[1]))
print(issue.get("org", ""), (issue.get("project") or {}).get("slug", ""), sep="\t")
PY
)
if [[ "$ISSUE_ORG" != "artisanal-software" || "$ISSUE_PROJECT" != "podhaven" ]]; then
  echo "Error: issue JSON is not for PodHaven (${ISSUE_ORG}/${ISSUE_PROJECT})." >&2
  exit 1
fi

LIST_JSON="$(mktemp)"
MANIFEST="$(mktemp)"
trap 'rm -f "$LIST_JSON" "$MANIFEST"' EXIT

sentry_cmd api "projects/${ISSUE_ORG}/${ISSUE_PROJECT}/events/${EVENT_ID}/attachments/" --json \
  >"$LIST_JSON"

python3 - "$LIST_JSON" "$EVENT_ID" <<'PY'
import json
import sys

attachments = json.loads(open(sys.argv[1]).read())
event_id = sys.argv[2]
print(f"Event {event_id}: {len(attachments)} attachment(s)")
for row in attachments:
    size = row.get("size")
    size_text = f"{size} bytes" if size is not None else "unknown size"
    print(f"  - {row['id']}  {row['name']}  ({size_text})")
PY

if [[ "$DOWNLOAD_ALL" == "0" && "${#NAMES[@]}" -eq 0 ]]; then
  exit 0
fi

MANIFEST_ARGS=("$LIST_JSON" "$DOWNLOAD_ALL")
if [[ "${#NAMES[@]}" -gt 0 ]]; then
  MANIFEST_ARGS+=("${NAMES[@]}")
fi
python3 - "${MANIFEST_ARGS[@]}" >"$MANIFEST" <<'PY'
import base64
import json
import re
import sys
from pathlib import PurePosixPath

attachments = json.load(open(sys.argv[1]))
download_all = sys.argv[2] == "1"
wanted = set(sys.argv[3:])
selected = attachments if download_all else [row for row in attachments if row["name"] in wanted]
if wanted:
    missing = wanted - {row["name"] for row in selected}
    for name in sorted(missing):
        print(f"Warning: attachment not found: {name}", file=sys.stderr)
if not selected:
    raise SystemExit("Error: no matching attachments to download")

used = set()
for row in selected:
    attachment_id = str(row["id"])
    original = str(row.get("name") or "")
    basename = PurePosixPath(original.replace("\\", "/")).name
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", basename).lstrip(".")
    if not safe:
        safe = "attachment"
    if safe != original or safe in used:
        safe_id = re.sub(r"[^A-Za-z0-9._-]+", "_", attachment_id)
        safe = f"{safe_id}-{safe}"
    used.add(safe)
    encoded_id = base64.urlsafe_b64encode(attachment_id.encode()).decode()
    encoded_name = base64.urlsafe_b64encode(safe.encode()).decode()
    print(f"{encoded_id}\t{encoded_name}")
PY

mkdir -p "$DIR"
while IFS=$'\t' read -r ENCODED_ID ENCODED_FILENAME; do
  ATTACHMENT_ID="$(python3 -c 'import base64, sys; print(base64.urlsafe_b64decode(sys.argv[1]).decode())' "$ENCODED_ID")"
  FILENAME="$(python3 -c 'import base64, sys; print(base64.urlsafe_b64decode(sys.argv[1]).decode())' "$ENCODED_FILENAME")"
  TARGET="$(
    python3 - "$DIR" "$FILENAME" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
target = (root / sys.argv[2]).resolve()
try:
    target.relative_to(root)
except ValueError:
    raise SystemExit("Error: attachment path escaped destination")
print(target)
PY
  )"
  sentry_cmd api \
    "projects/${ISSUE_ORG}/${ISSUE_PROJECT}/events/${EVENT_ID}/attachments/${ATTACHMENT_ID}/?download=1" \
    >"$TARGET"
  echo "Downloaded ${FILENAME} -> ${TARGET}"
done <"$MANIFEST"
