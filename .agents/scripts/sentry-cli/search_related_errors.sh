#!/bin/bash
# Search error events in a time window via `sentry explore`.
#
# Usage:
#   search_related_errors.sh --period PERIOD --query QUERY [--out FILE] [--limit N]
#
# Examples:
#   search_related_errors.sh --period '2026-05-30T00:10:00Z/2026-05-30T00:21:00Z' \
#     --query 'user.id:<uuid>'
#   search_related_errors.sh --period 90d --query 'user.id:<uuid>' --limit 25

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PERIOD=""
QUERY=""
OUT="/tmp/sentry_events_search.json"
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
    --out)
      OUT="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PERIOD" ]]; then
  echo "Usage: search_related_errors.sh --period PERIOD --query QUERY [--out FILE] [--limit N]" >&2
  exit 1
fi

require_sentry_auth

sentry_cmd explore "$SENTRY_TARGET" --dataset errors \
  --field issue --field title --field timestamp --field 'user.id' \
  --field release --field environment \
  --query "$QUERY" --period "$PERIOD" --limit "$LIMIT" --json > "$OUT"

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
