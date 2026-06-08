#!/bin/bash
# Integration tests for PodHaven Sentry skill scripts (repo-local only).
# Requires Sentry auth (~/.sentryclirc or SENTRY_AUTH_TOKEN) and network.

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SENTRY_CLI="${SKILLS_DIR}/sentry-cli"
FETCH_LOGS="${SKILLS_DIR}/analyze-sentry-logs/fetch_sentry_logs.sh"
FILTER_LOGS="${SKILLS_DIR}/analyze-sentry-logs/filter_sentry_logs.py"

# shellcheck source=lib.sh
source "${SENTRY_CLI}/lib.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

require_sentry_auth || fail "auth"

TMP="$(mktemp -d /tmp/podhaven_sentry_test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "=== fetch_issue_bundle ==="
bash "${SENTRY_CLI}/fetch_issue_bundle.sh" PODHAVEN-3W --out "$TMP/issue" --events 2
test -f "$TMP/issue/issue.json"
test -f "$TMP/issue/events.json"
pass fetch_issue_bundle

echo "=== fetch_feedback_bundle ==="
bash "${SENTRY_CLI}/fetch_feedback_bundle.sh" podhaven:7514780545 --out "$TMP/feedback"
test -f "$TMP/feedback/attachments.json"
pass fetch_feedback_bundle

echo "=== download_event_attachments ==="
EVENT="$(python3 -c "import json; print(json.load(open('$TMP/feedback/events.json'))['data'][0]['id'])")"
bash "${SENTRY_CLI}/download_event_attachments.sh" --event "$EVENT" --dir "$TMP/download" --name log.ndjson
test -s "$TMP/download/log.ndjson"
pass download_event_attachments

echo "=== search_related_errors ==="
bash "${SENTRY_CLI}/search_related_errors.sh" --period 90d \
  --query 'user.id:6B915F57-D7FC-4249-8FAD-B71F5D362CEB' \
  --out "$TMP/search.json" --limit 3
python3 -c "import json; assert len(json.load(open('$TMP/search.json'))['data']) >= 1"
pass search_related_errors

echo "=== fetch_sentry_logs ==="
bash "$FETCH_LOGS" 7d 'severity:[warn,error]' >/dev/null
test -f /tmp/sentry_logs_detail.json
python3 "$FILTER_LOGS" --around-ms 1780100431000 --window-ms 600000 --oneline >/dev/null
pass fetch_sentry_logs

echo
echo "All PodHaven Sentry skill tests passed."
