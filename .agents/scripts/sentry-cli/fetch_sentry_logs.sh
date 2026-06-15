#!/bin/bash
# Fetches Sentry structured logs via the `sentry` CLI (log list + explore).
#
# Usage:
#   fetch_sentry_logs.sh <statsPeriod> [query]
#
# Examples:
#   fetch_sentry_logs.sh 10h
#   fetch_sentry_logs.sh 2d "severity:warn"
#   fetch_sentry_logs.sh 6h 'user.id:<uuid> severity:[warn,error]'
#   fetch_sentry_logs.sh 6h 'trace:<trace_id> severity:[warn,error]'
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
#   /tmp/sentry_logs_detail.json   — individual entries (up to 1000)
#   /tmp/sentry_logs_summary.json  — aggregated counts by severity + message
#
# Requires: `sentry` CLI on PATH (or npx fallback) and Sentry auth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

STATS_PERIOD="${1:?Usage: fetch_sentry_logs.sh <statsPeriod> [query]}"
QUERY="${2:-severity:[warn,error]}"

require_sentry_auth

sentry_cmd explore "$SENTRY_TARGET" --dataset logs \
  --field severity --field message --field 'count()' \
  --query "$QUERY" --period "$STATS_PERIOD" --limit 100 --json \
  > /tmp/sentry_logs_summary.json

sentry_cmd log list "$SENTRY_TARGET" \
  --query "$QUERY" --period "$STATS_PERIOD" --limit 1000 --json \
  > /tmp/sentry_logs_detail.json

python3 - <<'PY'
import json

with open("/tmp/sentry_logs_detail.json") as f:
    detail = json.load(f)
with open("/tmp/sentry_logs_summary.json") as f:
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
PY
