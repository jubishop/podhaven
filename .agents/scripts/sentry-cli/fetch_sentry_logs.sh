#!/bin/bash
# Fetches Sentry structured logs via the `sentry` CLI (log list + explore).
#
# Usage:
#   fetch_sentry_logs.sh <statsPeriod> --out DIR [--query QUERY]
#
# Examples:
#   fetch_sentry_logs.sh 10h --out /tmp/podhaven-logs
#   fetch_sentry_logs.sh 6h --out /tmp/podhaven-logs \
#     --query 'user.id:<uuid> severity:[warn,error]'
#
# Query notes:
#   Prefer severity:[error,warn] over "severity:warn OR severity:error"
#   user.id:<uuid>  — PodHaven device IDFV
#   trace:<trace_id> — logs sharing a trace with an error event
#
# PodHaven: error events often tag environment:testFlight while structured logs
# tag environment:deployed. Prefer user.id (+ optional release) over environment.
#
# Outputs:
#   <out>/detail.json   — individual entries (up to 1000)
#   <out>/summary.json  — aggregated counts by severity + message
#
# Requires: `sentry` CLI on PATH and Sentry auth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '1,24p' "$0"
  exit 0
fi

STATS_PERIOD="${1:-}"
if [[ -n "$STATS_PERIOD" ]]; then
  shift
fi
OUT=""
QUERY="severity:[warn,error]"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT="$2"
      shift 2
      ;;
    --query)
      QUERY="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '1,26p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STATS_PERIOD" || -z "$OUT" ]]; then
  echo "Usage: fetch_sentry_logs.sh <statsPeriod> --out DIR [--query QUERY]" >&2
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

sentry_cmd explore "$SENTRY_TARGET" --dataset logs \
  --field severity --field message --field 'count()' \
  --query "$QUERY" --period "$STATS_PERIOD" --limit 100 --json \
  >"${OUT}/summary.json"

sentry_cmd log list "$SENTRY_TARGET" \
  --query "$QUERY" --period "$STATS_PERIOD" --limit 1000 --json \
  >"${OUT}/detail.json"

python3 - "${OUT}/detail.json" "${OUT}/summary.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    detail = json.load(f)
with open(sys.argv[2]) as f:
    summary = json.load(f)

total = len(detail.get("data", []))
has_more = detail.get("hasMore", False)
print(f"Fetched {total} individual log entries", end="")
if has_more:
    print(" (more available — narrow query or period)", end="")
print()
print()
print("Count | Severity | Message")
print("------|----------|--------")
for row in summary.get("data", []):
    count = int(row["count()"])
    sev = row["severity"]
    msg = row["message"][:120]
    print(f"{count:>5} | {sev:<8} | {msg}")
print()
print(f"Output: {sys.argv[1]} and {sys.argv[2]}")
PY
