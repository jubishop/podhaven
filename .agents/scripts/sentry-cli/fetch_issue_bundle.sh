#!/bin/bash
# Fetch issue metadata, representative events, and tag distribution via `sentry` CLI.
#
# Usage:
#   fetch_issue_bundle.sh <issue-ref> --out DIR [--events N] [--event-query QUERY]
#                         [--spans DEPTH]
#
# Examples:
#   fetch_issue_bundle.sh PODHAVEN-3W --out /tmp/podhaven-issue/issue
#   fetch_issue_bundle.sh 7505772270 --out /tmp/podhaven-issue/issue --events 2
#   fetch_issue_bundle.sh PODHAVEN-3W --out /tmp/podhaven-issue/issue --spans all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISSUE_REF=""
OUT=""
EVENTS=3
EVENT_QUERY=""
SPANS=""

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
    --spans)
      SPANS="$2"
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

if [[ -z "$ISSUE_REF" || -z "$OUT" ]]; then
  echo "Usage: fetch_issue_bundle.sh <issue-ref> --out DIR [--events N] [--event-query QUERY] [--spans DEPTH]" >&2
  exit 1
fi

if [[ -L "$OUT" ]]; then
  echo "Error: output directory must not be a symbolic link: $OUT" >&2
  exit 1
fi
if [[ -d "$OUT" ]] && [[ -n "$(find "$OUT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Error: output directory must be empty: $OUT" >&2
  exit 1
fi

require_sentry_auth
mkdir -p "$OUT"

ISSUE_ID="$(
  python3 - "$ISSUE_REF" <<'PY'
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

VIEW_ARGS=(issue view "$ISSUE_ID" --fresh --json)
if [[ -n "$SPANS" ]]; then
  VIEW_ARGS+=(--spans "$SPANS")
fi
sentry_cmd "${VIEW_ARGS[@]}" >"${OUT}/issue.json"

IFS=$'\t' read -r NUMERIC_ID SHORT_ID ISSUE_ORG ISSUE_PROJECT FIRST_SEEN < <(
  python3 - "${OUT}/issue.json" <<'PY'
import json
import sys

issue = json.load(open(sys.argv[1]))
project = issue.get("project") or {}
print(
    issue.get("id", ""),
    issue.get("shortId", ""),
    issue.get("org", ""),
    project.get("slug", ""),
    issue.get("firstSeen", ""),
    sep="\t",
)
PY
)

if [[ "$ISSUE_ORG" != "artisanal-software" || "$ISSUE_PROJECT" != "podhaven" ]]; then
  echo "Error: ${SHORT_ID:-issue} is not a PodHaven issue (${ISSUE_ORG}/${ISSUE_PROJECT})." >&2
  exit 1
fi
if [[ -z "$FIRST_SEEN" ]]; then
  echo "Error: ${SHORT_ID} has no firstSeen timestamp." >&2
  exit 1
fi

EVENT_ARGS=(issue events "$ISSUE_ID" --full --fresh --json --limit "$EVENTS" --period ">=${FIRST_SEEN}")
if [[ -n "$EVENT_QUERY" ]]; then
  EVENT_ARGS+=(--query "$EVENT_QUERY")
fi
sentry_cmd "${EVENT_ARGS[@]}" >"${OUT}/events.json"

python3 - "$OUT" <<'PY'
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
payload = json.loads((out / "events.json").read_text())
events = payload.get("data", [])
if not events:
    print("Error: No representative events matched the issue and requested filters.", file=sys.stderr)
    raise SystemExit(1)
for event in events:
    event_id = str(event.get("id") or "")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", event_id):
        print(f"Error: unsafe event ID in Sentry response: {event_id!r}", file=sys.stderr)
        raise SystemExit(1)
    path = out / f"event_{event_id}.json"
    path.write_text(json.dumps(event, indent=2) + "\n")
PY

TAG_KEYS=(environment release device os user)
for key in "${TAG_KEYS[@]}"; do
  if sentry_cmd api "organizations/${ISSUE_ORG}/issues/${NUMERIC_ID}/tags/${key}/values/" --json \
    >"${OUT}/tags_${key}.json" 2>/dev/null; then
    :
  else
    echo '[]' >"${OUT}/tags_${key}.json"
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
