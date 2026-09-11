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
#   Defaults to warnings/errors unless QUERY explicitly selects severity/level.
#   Use severity:* to request all levels. Scope filters preserve the default.
#   user.id:<uuid>  — PodHaven device IDFV
#   trace:<trace_id> — logs sharing a trace with an error event
#
# PodHaven: error events often tag environment:testFlight while structured logs
# tag environment:deployed. Prefer user.id (+ optional release) over environment.
#
# Outputs:
#   <out>/detail.json   — individual entries (up to 1000; may be a sample)
#   <out>/summary.json  — counts by severity + message across all pages
#   <out>/coverage.json — fixed window, effective query, and coverage status
#
# Requires: `sentry` CLI on PATH and Sentry auth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '1,26p' "$0"
  exit 0
fi

STATS_PERIOD="${1:-}"
if [[ -n "$STATS_PERIOD" ]]; then
  shift
fi
OUT=""
QUERY=""

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

python3 "${SCRIPT_DIR}/collect_sentry_logs.py" \
  --sentry "$(sentry_bin)" --target "$SENTRY_TARGET" \
  --period "$STATS_PERIOD" --out "$OUT" --query "$QUERY"
