#!/bin/bash
# Fetches PodHaven's Sentry structured logs via the `sentry` CLI: complete
# counts for every message in one fixed window (explore, all pages) and a
# detail sample of individual entries (log list).
#
# Usage:
#   fetch_sentry_logs.sh <period> --out DIR [--query QUERY]
#
#   <period> is a duration ending now (12h, 2d, 1w) or a bounded ISO range
#   with timezone offsets, START..END. Pass an earlier coverage.json's
#   `period` to sample again within the same window. DIR must be new or empty.
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
# PodHaven: logs sent before the app detects its environment carry
# environment:deployed. Prefer user.id (+ optional release) over environment.
#
# Outputs:
#   <out>/summary.json  — counts by severity + message across all pages
#   <out>/detail.json   — individual entries (up to 1000; may be a sample)
#   <out>/coverage.json — fixed `period`, effective `query`,
#     `counts_by_severity`, `summary` (complete|partial), `detail`
#     (complete|sample|unavailable), and `error` when a request failed
#
# Exits nonzero on failure. Once fetching starts, it first writes what it
# retrieved and records the error in coverage.json.
#
# Requires: `sentry` CLI on PATH and Sentry auth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
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
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STATS_PERIOD" || -z "$OUT" ]]; then
  echo "Usage: fetch_sentry_logs.sh <period> --out DIR [--query QUERY]" >&2
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
