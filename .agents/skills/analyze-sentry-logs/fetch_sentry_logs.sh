#!/bin/bash
# Fetches Sentry logs via the REST API (dataset=ourlogs).
#
# Usage:
#   fetch_sentry_logs.sh <statsPeriod> [query]
#
# Examples:
#   fetch_sentry_logs.sh 10h                         # all warn+error logs, last 10 hours
#   fetch_sentry_logs.sh 2d "severity:warn"          # warn only, last 2 days
#   fetch_sentry_logs.sh 1h "severity:error"         # error only, last hour
#   fetch_sentry_logs.sh 6h 'user.id:<uuid> (severity:warn OR severity:error)'
#   fetch_sentry_logs.sh 7d 'user.id:<uuid> release:com.app@1.0+510'
#   fetch_sentry_logs.sh 6h "message:*timeout*"      # messages matching wildcard
#
# After fetch, narrow to an incident window:
#   python3 filter_sentry_logs.py --around-ms <event_epoch_ms> --window-ms 600000 --oneline
#
# Query syntax (Sentry search):
#   severity:error                    — exact match
#   !severity:debug                   — negation
#   severity:warn OR severity:error   — boolean OR
#   message:"*timeout*"               — wildcard in message
#   has:trace                         — field exists
#   release:1.2.3                     — by release (works on logs)
#   user.id:<uuid>                    — logs for one Sentry user (PodHaven: device IDFV)
#   trace:<trace_id>                  — logs sharing a trace with an error event
#
# PodHaven note: error events often tag environment:testFlight while structured
# logs usually tag environment:deployed. Prefer user.id (+ release) over
# environment: when correlating issue events to logs.
#
# Outputs:
#   /tmp/sentry_logs_detail.json   — individual entries (up to 9999), newest first
#   /tmp/sentry_logs_summary.json  — aggregated counts by severity+message
#   stdout                         — summary table
#
# Requires: ~/.sentryclirc with [auth] token=...

set -euo pipefail

STATS_PERIOD="${1:?Usage: fetch_sentry_logs.sh <statsPeriod> [query]}"
QUERY="${2:-severity:warn OR severity:error}"

ORG="artisanal-software"
PROJECT_ID="4508469264711681"
BASE_URL="https://us.sentry.io/api/0/organizations/${ORG}/events"

AUTH_TOKEN=$(awk -F= '/^token=/{print $2}' ~/.sentryclirc)
if [[ -z "$AUTH_TOKEN" ]]; then
  echo "Error: No auth token found in ~/.sentryclirc" >&2
  exit 1
fi

AUTH_HEADER="Authorization: Bearer ${AUTH_TOKEN}"

# URL-encode the query
ENCODED_QUERY=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")

# Detail fields: timestamp, severity, message, plus correlation context
DETAIL_FIELDS="field=timestamp&field=severity&field=message&field=trace&field=release&field=environment&field=user.id"

# Fetch individual entries (max per_page for ourlogs is 9999)
curl -sf -H "$AUTH_HEADER" \
  "${BASE_URL}/?dataset=ourlogs&project=${PROJECT_ID}&${DETAIL_FIELDS}&per_page=9999&statsPeriod=${STATS_PERIOD}&sort=-timestamp&query=${ENCODED_QUERY}" \
  > /tmp/sentry_logs_detail.json

# Fetch aggregated counts
curl -sf -H "$AUTH_HEADER" \
  "${BASE_URL}/?dataset=ourlogs&project=${PROJECT_ID}&field=severity&field=message&field=count()&per_page=100&statsPeriod=${STATS_PERIOD}&sort=-count()&query=${ENCODED_QUERY}" \
  > /tmp/sentry_logs_summary.json

# Print summary to stdout
python3 -c "
import json

with open('/tmp/sentry_logs_detail.json') as f:
    detail = json.load(f)
with open('/tmp/sentry_logs_summary.json') as f:
    summary = json.load(f)

total = len(detail.get('data', []))
print(f'Fetched {total} individual log entries')
print()
print('Count | Severity | Message')
print('------|----------|--------')
for row in summary.get('data', []):
    count = int(row['count()'])
    sev = row['severity']
    msg = row['message'][:120]
    print(f'{count:>5} | {sev:<8} | {msg}')
"
