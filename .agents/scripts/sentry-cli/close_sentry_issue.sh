#!/bin/bash
# Close a PodHaven Sentry error issue or feedback item once its tracking work
# is done, then read it back and fail unless Sentry recorded the closure.
#
# Usage:
#   close_sentry_issue.sh ISSUE_ID (--commit SHA | --next | --archive | --resolve)
#
#   ISSUE_ID      The numeric Sentry issue ID.
#   --commit SHA  A merged commit, given as its full SHA, fixes the error:
#                 resolve the issue in it, so only builds that contain the fix
#                 regress it. An already resolved issue is reopened first,
#                 since Sentry ignores the request otherwise. If Sentry rejects
#                 the commit, the issue is resolved in the next release.
#   --next        The work closes without a fix commit, such as a stale-build
#                 recurrence: resolve the issue in the next release.
#   --archive     The error is accepted as expected behavior: archive the issue
#                 until it escalates, so the daily intake ignores it.
#   --resolve     A feedback item's work is done: resolve it plainly, since a
#                 feedback submission gets no later events for a commit or
#                 release resolution to guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

USAGE="Usage: close_sentry_issue.sh ISSUE_ID (--commit SHA | --next | --archive | --resolve)"
ISSUE_ID=""
MODE=""
COMMIT=""

usage_error() {
  echo "Error: $1" >&2
  echo "$USAGE" >&2
  exit 1
}

set_mode() {
  [[ -z "$MODE" ]] || usage_error "give exactly one of --commit, --next, --archive, or --resolve."
  MODE="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      [[ $# -ge 2 ]] || usage_error "--commit needs the merge commit's SHA."
      set_mode commit
      COMMIT="$2"
      shift 2
      ;;
    --next | --archive | --resolve)
      set_mode "${1#--}"
      shift
      ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    -*)
      usage_error "unknown argument: $1"
      ;;
    *)
      [[ -z "$ISSUE_ID" ]] || usage_error "give one issue ID."
      ISSUE_ID="$1"
      shift
      ;;
  esac
done

[[ "$ISSUE_ID" =~ ^[0-9]+$ ]] || usage_error "give the numeric Sentry issue ID."
[[ -n "$MODE" ]] || usage_error "give exactly one of --commit, --next, --archive, or --resolve."
if [[ "$MODE" == commit && ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  usage_error "--commit needs the full 40-character lowercase commit SHA."
fi

require_sentry_auth
ISSUE="${SENTRY_ORG}/${ISSUE_ID}"

# Prints the issue's status and, when Sentry recorded one, its resolving commit.
read_status() {
  local issue_json
  issue_json="$(sentry_cmd issue view "$ISSUE" --fresh --json --fields id,status,statusDetails)" || {
    echo "Error: could not read Sentry issue ${ISSUE_ID}." >&2
    return 1
  }
  python3 -c '
import json, sys
try:
    issue = json.loads(sys.argv[1])
    status = issue["status"]
    commit = (issue.get("statusDetails") or {}).get("inCommit") or {}
    print(status, commit.get("id") or "")
except (ValueError, KeyError, TypeError, AttributeError):
    sys.exit("Error: Sentry returned unreadable data for the issue.")
' "$issue_json"
}

STATE="$(read_status)"
read -r STATUS _ <<<"$STATE"
EXPECTED_COMMIT=""
REJECTED=0

case "$MODE" in
  commit)
    if [[ "$STATUS" == resolved ]]; then
      sentry_cmd issue unresolve "$ISSUE" >/dev/null
    fi
    if sentry_cmd issue resolve "$ISSUE" --in "@commit:jubishop/podhaven@${COMMIT}" >/dev/null; then
      EXPECTED_COMMIT="$COMMIT"
    else
      echo "Sentry rejected commit ${COMMIT}; resolving in the next release instead." >&2
      REJECTED=1
      sentry_cmd issue resolve "$ISSUE" --in @next >/dev/null
    fi
    EXPECTED=resolved
    ;;
  next)
    sentry_cmd issue resolve "$ISSUE" --in @next >/dev/null
    EXPECTED=resolved
    ;;
  archive)
    sentry_cmd issue archive "$ISSUE" --until auto >/dev/null
    EXPECTED=ignored
    ;;
  resolve)
    sentry_cmd issue resolve "$ISSUE" >/dev/null
    EXPECTED=resolved
    ;;
esac

STATE="$(read_status)"
read -r STATUS RECORDED_COMMIT <<<"$STATE"
if [[ "$STATUS" != "$EXPECTED" || (-n "$EXPECTED_COMMIT" && "$RECORDED_COMMIT" != "$EXPECTED_COMMIT") ]]; then
  echo "Error: Sentry did not record the closure: issue ${ISSUE_ID} reads status ${STATUS}${RECORDED_COMMIT:+ in commit ${RECORDED_COMMIT}}." >&2
  exit 1
fi

case "$MODE" in
  commit)
    if [[ "$REJECTED" == 1 ]]; then
      echo "Sentry issue ${ISSUE_ID} is resolved in the next release, because Sentry rejected commit ${COMMIT}."
    else
      echo "Sentry issue ${ISSUE_ID} is resolved in commit ${COMMIT}."
    fi
    ;;
  next) echo "Sentry issue ${ISSUE_ID} is resolved in the next release." ;;
  archive) echo "Sentry issue ${ISSUE_ID} is archived until it escalates." ;;
  resolve) echo "Sentry issue ${ISSUE_ID} is resolved." ;;
esac
