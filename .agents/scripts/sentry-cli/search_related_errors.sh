#!/bin/bash
# Search error events in a time window via `sentry explore`, newest first.
#
# Usage:
#   search_related_errors.sh --period PERIOD --query QUERY [--out FILE] [--limit N]
#   search_related_errors.sh --bundle DIR [--out FILE] [--limit N]
#
# --bundle reads a fetch_feedback_bundle.sh directory and searches the reporter's
# user.id from 10 minutes before the submission to 1 minute after, widening the
# start to 30 minutes before when that finds nothing. Without a user ID, it
# searches the event's release and environment and labels the matches
# release-wide. It prints the windows and query searched and the five matches
# nearest the submission, and saves the last search to FILE, by default
# DIR/related.json.
#
# Examples:
#   search_related_errors.sh --bundle /tmp/sentry_feedback.X/bundle
#   search_related_errors.sh --period '2026-05-30T00:10:00Z..2026-05-30T00:21:00Z' \
#     --query 'user.id:<uuid>'
#   search_related_errors.sh --period 90d --query 'user.id:<uuid>' --limit 25

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PERIOD=""
QUERY=""
BUNDLE=""
OUT=""
LIMIT=25

while [[ $# -gt 0 ]]; do
  case "$1" in
    --period)
      PERIOD="$2"
      shift 2
      ;;
    --query)
      QUERY="$2"
      shift 2
      ;;
    --bundle)
      BUNDLE="$2"
      shift 2
      ;;
    --out)
      OUT="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$BUNDLE" && (-n "$PERIOD" || -n "$QUERY") ]]; then
  echo "Error: --bundle derives the window and query; drop --period and --query." >&2
  exit 1
fi
if [[ -z "$BUNDLE" && -z "$PERIOD" ]]; then
  echo "Usage: search_related_errors.sh --period PERIOD --query QUERY [--out FILE] [--limit N]" >&2
  echo "       search_related_errors.sh --bundle DIR [--out FILE] [--limit N]" >&2
  exit 1
fi

search() {
  sentry_cmd explore "$SENTRY_TARGET" --dataset errors \
    --field issue --field title --field timestamp --field 'user.id' \
    --field release --field environment \
    --query "$2" --period "$1" --sort=-timestamp --limit "$LIMIT" --json > "$OUT"
}

if [[ -z "$BUNDLE" ]]; then
  OUT="${OUT:-/tmp/sentry_events_search.json}"
  require_sentry_auth
  search "$PERIOD" "$QUERY"
  python3 - "$OUT" "$PERIOD" "$QUERY" <<'PY'
import json
import sys

out, period, query = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.load(open(out))
rows = payload.get("data", [])
print(f"Matched {len(rows)} events")
print(f"Period: {period}")
print(f"Query: {query}")
print(f"Output: {out}")
print()
for row in rows:
    print(
        f"  {row.get('timestamp')}  {row.get('issue')}  "
        f"{(row.get('title') or '')[:80]}  user.id={row.get('user.id')}"
    )
PY
  exit 0
fi

OUT="${OUT:-${BUNDLE}/related.json}"
PLAN="$(python3 - "$BUNDLE" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone

path = f"{sys.argv[1]}/events.json"
try:
    event = json.load(open(path))["data"][0]
    submitted = datetime.fromisoformat(event["dateCreated"])
except (OSError, ValueError, LookupError, TypeError) as error:
    raise SystemExit(f"Error: no feedback event with a dateCreated in {path}: {error!r}")
if submitted.tzinfo is None:
    submitted = submitted.replace(tzinfo=timezone.utc)
tags = {tag.get("key"): tag.get("value") for tag in event.get("tags") or []}
user_id = (event.get("user") or {}).get("id")
if user_id:
    query, scope = f"user.id:{user_id}", "same-user"
elif tags.get("release") and tags.get("environment"):
    query, scope = f"release:{tags['release']} environment:{tags['environment']}", "release-wide"
else:
    raise SystemExit("Error: the feedback event has no user ID, or no release and environment, to search by")


def at(minutes):
    return (submitted + timedelta(minutes=minutes)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


print(f"{at(-10)}..{at(1)}")
print(f"{at(-30)}..{at(1)}")
print(query)
print(scope)
print(submitted.isoformat())
PY
)"
{
  read -r NARROW
  read -r WIDE
  read -r QUERY
  read -r SCOPE
  read -r SUBMITTED
} <<<"$PLAN"

require_sentry_auth
search "$NARROW" "$QUERY"
SEARCHED="$NARROW"
if python3 -c 'import json, sys; sys.exit(bool(json.load(open(sys.argv[1])).get("data")))' "$OUT"; then
  search "$WIDE" "$QUERY"
  SEARCHED="$NARROW, then $WIDE"
fi

python3 - "$OUT" "$SUBMITTED" "$QUERY" "$SCOPE" "$SEARCHED" <<'PY'
import json
import sys
from datetime import datetime

out, submitted, query, scope, searched = sys.argv[1:]
moment = datetime.fromisoformat(submitted)
rows = []
for row in json.load(open(out)).get("data", []):
    offset = int((datetime.fromisoformat(row["timestamp"]) - moment).total_seconds())
    rows.append((abs(offset), offset, row))
rows.sort(key=lambda entry: entry[0])
print(f"Submitted: {submitted}")
print(f"Query: {query} ({scope})")
print(f"Window: {searched}")
print(f"Matched {len(rows)} events{'; nearest the submission first:' if rows else ''}")
for _, offset, row in rows[:5]:
    minutes, seconds = divmod(abs(offset), 60)
    print(
        f"  {'-' if offset < 0 else '+'}{minutes}m{seconds:02d}s  {row.get('timestamp')}  "
        f"{row.get('issue')}  {(row.get('title') or '')[:80]}"
    )
if len(rows) > 5:
    print(f"  {len(rows) - 5} more in the output")
print(f"Output: {out}")
PY
