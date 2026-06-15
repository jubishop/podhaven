#!/bin/bash
# Fetch feedback issue, event, activity, notes, and attachment metadata via `sentry` CLI.
#
# Usage:
#   fetch_feedback_bundle.sh <slug-or-url> [--out DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

SLUG=""
OUT="/tmp/sentry_feedback"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
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

if [[ -z "$SLUG" ]]; then
  echo "Usage: fetch_feedback_bundle.sh <slug-or-url> [--out DIR]" >&2
  exit 1
fi

require_sentry_auth
mkdir -p "$OUT"

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

python3 - "${OUT}/events.json" <<'PY' || EVENTS_FALLBACK=1
import json
import sys

rows = json.load(open(sys.argv[1])).get("data", [])
if not rows:
    raise SystemExit(1)
PY

if [[ "${EVENTS_FALLBACK:-0}" == "1" ]]; then
  sentry_cmd api "organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/events/?full=true&limit=1" --json \
    > "${OUT}/events_raw.json"
  python3 - "${OUT}/events_raw.json" "${OUT}/events.json" <<'PY'
import json
import sys

raw = json.load(open(sys.argv[1]))
rows = raw if isinstance(raw, list) else raw.get("data", [])
json.dump({"data": rows}, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
fi

python3 - "$OUT" <<'PY'
import json
from pathlib import Path
import sys

out = Path(sys.argv[1])
payload = json.loads((out / "events.json").read_text())
for event in payload.get("data", []):
    (out / f"event_{event['id']}.json").write_text(json.dumps(event, indent=2) + "\n")
PY

sentry_cmd api "organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/activities/" --json \
  > "${OUT}/activities.json" 2>/dev/null || echo '{"activity":[]}' > "${OUT}/activities.json"
sentry_cmd api "organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/notes/" --json \
  > "${OUT}/notes.json" 2>/dev/null || echo '[]' > "${OUT}/notes.json"

EVENT_ID="$(python3 -c "import json; d=json.load(open('${OUT}/events.json')); print(d['data'][0]['id'])")"
sentry_cmd api "projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/${EVENT_ID}/attachments/" --json \
  > "${OUT}/attachments.json"

python3 - "$OUT" "$ISSUE_ID" <<'PY'
import json
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
print(f"  Output: {out}")
print()
print("Message:")
print(f"> {message}")
PY
