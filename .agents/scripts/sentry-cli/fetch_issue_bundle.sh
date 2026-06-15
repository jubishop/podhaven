#!/bin/bash
# Fetch issue metadata, representative events, and tag distribution via `sentry` CLI.
#
# Usage:
#   fetch_issue_bundle.sh <issue-ref> [--out DIR] [--events N] [--event-query QUERY]
#
# Examples:
#   fetch_issue_bundle.sh PODHAVEN-3W
#   fetch_issue_bundle.sh 7505772270 --events 2 --event-query 'environment:testFlight'
#   fetch_issue_bundle.sh 'https://artisanal-software.sentry.io/issues/7505772270/'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISSUE_REF=""
OUT="/tmp/sentry_issue"
EVENTS=3
EVENT_QUERY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT="$2"
      shift 2
      ;;
    --events)
      EVENTS="$2"
      shift 2
      ;;
    --event-query)
      EVENT_QUERY="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$ISSUE_REF" ]]; then
        ISSUE_REF="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$ISSUE_REF" ]]; then
  echo "Usage: fetch_issue_bundle.sh <issue-ref> [--out DIR] [--events N] [--event-query QUERY]" >&2
  exit 1
fi

require_sentry_auth
mkdir -p "$OUT"

ISSUE_ID="$(python3 - "$ISSUE_REF" <<'PY'
import re
import sys

ref = sys.argv[1].strip()
match = re.search(r"/issues/(?P<id>\d+)(?:/|$|\?)", ref)
if match:
    print(match.group("id"))
    raise SystemExit
if ref.isdigit():
    print(ref)
    raise SystemExit
print(ref)
PY
)"

sentry_cmd issue view "$ISSUE_ID" --json > "${OUT}/issue.json"

NUMERIC_ID="$(python3 -c "import json; print(json.load(open('${OUT}/issue.json'))['id'])")"
SHORT_ID="$(python3 -c "import json; print(json.load(open('${OUT}/issue.json'))['shortId'])")"

EVENT_ARGS=(issue events "$ISSUE_ID" --full --json --limit "$EVENTS")
if [[ -n "$EVENT_QUERY" ]]; then
  EVENT_ARGS+=(--query "$EVENT_QUERY")
fi
sentry_cmd "${EVENT_ARGS[@]}" > "${OUT}/events.json"

python3 - "$OUT" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
payload = json.loads((out / "events.json").read_text())
for event in payload.get("data", []):
    path = out / f"event_{event['id']}.json"
    path.write_text(json.dumps(event, indent=2) + "\n")
PY

TAG_KEYS=(environment release device os user)
for key in "${TAG_KEYS[@]}"; do
  if sentry_cmd api "organizations/${SENTRY_ORG}/issues/${NUMERIC_ID}/tags/${key}/values/" --json \
    > "${OUT}/tags_${key}.json" 2>/dev/null; then
    :
  else
    echo '[]' > "${OUT}/tags_${key}.json"
  fi
done

python3 - "$OUT" <<'PY'
import json
import sys

out = sys.argv[1]
issue = json.load(open(f"{out}/issue.json"))
events = json.load(open(f"{out}/events.json")).get("data", [])
print(f"Issue {issue.get('shortId')} — {issue.get('title')}")
print(f"  Status: {issue.get('status')}  Level: {issue.get('level')}")
print(f"  Events: {issue.get('count')}  Users: {issue.get('userCount')}")
print(f"  First seen: {issue.get('firstSeen')}  Last seen: {issue.get('lastSeen')}")
print(f"  Output: {out}")
print()
print("Representative events:")
for event in events:
    entries = {entry["type"]: entry for entry in event.get("entries", [])}
    exc = (entries.get("exception") or {}).get("values") or [{}]
    top = exc[0]
    print(
        f"  - {event.get('id')}  {event.get('dateCreated')}  "
        f"{top.get('type') or event.get('title')}: {(top.get('value') or '')[:80]}"
    )
print()
print("Tag distribution:")
for key in ("environment", "release", "device", "os", "user"):
    path = f"{out}/tags_{key}.json"
    try:
        values = json.load(open(path))
    except (OSError, json.JSONDecodeError):
        continue
    if not values:
        continue
    top = ", ".join(f"{row.get('value')} ({row.get('count')})" for row in values[:5])
    print(f"  {key}: {top}")
PY
