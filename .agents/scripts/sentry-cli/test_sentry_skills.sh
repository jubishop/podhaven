#!/bin/bash
# Integration tests for PodHaven Sentry skill scripts (repo-local only).
# Requires Sentry auth (~/.sentryclirc or SENTRY_AUTH_TOKEN) and network.

set -euo pipefail

SENTRY_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH_LOGS="${SENTRY_CLI}/fetch_sentry_logs.sh"
FILTER_LOGS="${SENTRY_CLI}/filter_sentry_logs.py"

# shellcheck source=lib.sh
source "${SENTRY_CLI}/lib.sh"

pass() { echo "PASS: $*"; }
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_sentry_auth || fail "auth"

TMP="$(mktemp -d /tmp/podhaven_sentry_test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "=== fetch_issue_bundle ==="
LATEST_ISSUE="$(sentry_cmd issue list "$SENTRY_TARGET" --period 30d --limit 1 --sort date --fresh --json |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["data"][0]["shortId"])')"
bash "${SENTRY_CLI}/fetch_issue_bundle.sh" "$LATEST_ISSUE" --out "$TMP/issue" --events 2
test -f "$TMP/issue/issue.json"
test -f "$TMP/issue/events.json"
python3 -c "import json; assert json.load(open('$TMP/issue/events.json'))['data']"
test -n "$(find "$TMP/issue" -name 'event_*.json' -type f -print -quit)"
pass fetch_issue_bundle

echo "=== fetch_feedback_bundle ==="
if [[ -n "${SENTRY_TEST_FEEDBACK_SLUG:-}" ]]; then
  bash "${SENTRY_CLI}/fetch_feedback_bundle.sh" "$SENTRY_TEST_FEEDBACK_SLUG" --out "$TMP/feedback"
  test -f "$TMP/feedback/attachments.json"
  pass fetch_feedback_bundle
else
  echo "SKIP: set SENTRY_TEST_FEEDBACK_SLUG to exercise a current feedback fixture"
fi

echo "=== search_related_errors ==="
if [[ -n "${SENTRY_TEST_USER_ID:-}" ]]; then
  bash "${SENTRY_CLI}/search_related_errors.sh" --period 90d \
    --query "user.id:${SENTRY_TEST_USER_ID}" --out "$TMP/search.json" --limit 3
  python3 -c "import json; assert json.load(open('$TMP/search.json'))['data']"
  pass search_related_errors
else
  echo "SKIP: set SENTRY_TEST_USER_ID to exercise a current user fixture"
fi

echo "=== fetch_sentry_logs ==="
bash "$FETCH_LOGS" 7d --out "$TMP/logs" --query 'severity:[warn,error]' >/dev/null
test -f "$TMP/logs/detail.json"
AROUND_MS="$(python3 -c "import json; row=json.load(open('$TMP/logs/detail.json'))['data'][0]; print(int(float(row['timestamp_precise']) // 1_000_000))")"
python3 "$FILTER_LOGS" --input "$TMP/logs/detail.json" \
  --output "$TMP/logs/filtered.json" --around-ms "$AROUND_MS" \
  --window-ms 1200000 --oneline >/dev/null
python3 -c "import json; assert json.load(open('$TMP/logs/filtered.json'))['data']"
pass fetch_sentry_logs

echo
echo "All PodHaven Sentry skill tests passed."
