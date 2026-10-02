#!/bin/bash
# Fetch feedback issue, event, activity, notes, and attachment metadata via `sentry` CLI.
#
# Usage:
#   fetch_feedback_bundle.sh <slug-or-url> --out DIR
#   DIR must not already exist; use a fresh path for each fetch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

SLUG=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Error: --out DIR requires a fresh output directory path." >&2
        exit 1
      fi
      OUT="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '1,8p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$SLUG" ]]; then
        SLUG="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$SLUG" || -z "$OUT" ]]; then
  echo "Usage: fetch_feedback_bundle.sh <slug-or-url> --out DIR" >&2
  exit 1
fi

while [[ "$OUT" == */ && "$OUT" != "/" ]]; do
  OUT="${OUT%/}"
done

if [[ -e "$OUT" || -L "$OUT" ]]; then
  echo "Error: output directory must not already exist; choose a fresh path: $OUT" >&2
  exit 1
fi

require_sentry_auth
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT"

ISSUE_ID="$(python3 - "$SLUG" <<'PY'
import re
import sys
import urllib.parse

ref = urllib.parse.unquote(sys.argv[1].strip())
slug_match = re.search(r"feedbackSlug=(?P<slug>[^&]+)", ref, re.IGNORECASE)
if slug_match:
    ref = urllib.parse.unquote(slug_match.group("slug"))
issue_match = re.search(r"/issues/(?P<id>\d+)(?:/|$|\?)", ref)
if issue_match:
    print(issue_match.group("id"))
    raise SystemExit
if ref.isdigit():
    print(ref)
    raise SystemExit
if ":" in ref:
    _, numeric = ref.split(":", 1)
    if numeric.isdigit():
        print(numeric)
        raise SystemExit
print(ref)
PY
)"

sentry_cmd issue view "$ISSUE_ID" --json > "${OUT}/issue.json"

sentry_cmd issue events "$ISSUE_ID" --full --json --limit 1 > "${OUT}/events.json"

EVENT_COUNT="$(python3 - "${OUT}/events.json" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1]))
except (OSError, ValueError) as error:
    raise SystemExit(f"Error: unable to read native issue events: {error}")
if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
    raise SystemExit("Error: expected native issue events to contain a data list")
print(len(payload["data"]))
PY
)"

if [[ "$EVENT_COUNT" == "0" ]]; then
  sentry_api_json "organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/events/?full=true&limit=1" \
    events "${OUT}/events_raw.json"
  python3 - "${OUT}/events_raw.json" "${OUT}/events.json" <<'PY'
import json
import sys

rows = json.load(open(sys.argv[1]))
json.dump({"data": rows}, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
fi

EVENT_ID="$(python3 - "$OUT" <<'PY'
import json
from pathlib import Path
import re
import sys

out = Path(sys.argv[1])
payload = json.loads((out / "events.json").read_text())
events = payload["data"]
if not events:
    raise SystemExit("Error: No representative events available for this feedback.")
for event in events:
    if not isinstance(event, dict) or not isinstance(event.get("id"), str):
        raise SystemExit("Error: expected a feedback event with an ID")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", event["id"]):
        raise SystemExit("Error: unsafe event ID in Sentry response")
for event in events:
    (out / f"event_{event['id']}.json").write_text(json.dumps(event, indent=2) + "\n")
print(events[0]["id"])
PY
)"

if ! sentry_api_json "organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/activities/" \
  activity "${OUT}/activities.json"; then
  echo "Warning: feedback activities unavailable; no activity file was saved." >&2
fi
if ! sentry_api_json "organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/notes/" \
  notes "${OUT}/notes.json"; then
  echo "Warning: feedback notes unavailable; no notes file was saved." >&2
fi

sentry_api_json "projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/${EVENT_ID}/attachments/" \
  attachments "${OUT}/attachments.json"

python3 - "$OUT" "$ISSUE_ID" <<'PY'
import json
from pathlib import Path
import sys

out, issue_id = sys.argv[1], sys.argv[2]
issue = json.load(open(f"{out}/issue.json"))
events = json.load(open(f"{out}/events.json")).get("data", [])
attachments = json.load(open(f"{out}/attachments.json"))
metadata = issue.get("metadata") or {}
message = metadata.get("message") or issue.get("title")
event = events[0] if events else {}
print(f"Feedback podhaven:{issue_id} — {issue.get('shortId')}")
print(f"  Submitted: {event.get('dateCreated', issue.get('lastSeen'))}")
tags = {tag["key"]: tag["value"] for tag in event.get("tags", [])}
print(f"  Release: {tags.get('release', 'unknown')}  Env: {tags.get('environment', 'unknown')}")
print(f"  Event: {event.get('id', 'none')}")
print(f"  Attachments: {', '.join(row['name'] for row in attachments) or 'none'}")
for filename, label in (("activities.json", "Activities"), ("notes.json", "Notes")):
    path = Path(out) / filename
    if not path.exists():
        print(f"  {label}: unavailable")
        continue
    payload = json.loads(path.read_text())
    rows = payload["activity"] if filename == "activities.json" else payload
    print(f"  {label}: {len(rows)}")
print(f"  Output: {out}")
print()
print("Message:")
print(f"> {message}")
PY
