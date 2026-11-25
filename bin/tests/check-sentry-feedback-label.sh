#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-sentry-feedback-label.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

STUBS="$TEST_DIR/bin"
CAPTURE="$TEST_DIR/capture"
mkdir -p "$STUBS" "$CAPTURE"

cat > "$STUBS/sentry" <<'EOF'
#!/bin/sh
if [ "$1 $2" = 'auth status' ]; then
  exit 0
fi
if [ "$1 $2" = 'issue list' ]; then
  printf '%s\n' '{"data":[{"id":"7485822944","shortId":"PODHAVEN-3K","permalink":"https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A7485822944"},{"id":"7485822945","shortId":"PODHAVEN-3L","permalink":"https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A7485822945"}]}'
  exit 0
fi
exit 97
EOF
chmod +x "$STUBS/sentry"

cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
if [ "$1" = api ] && [ "$4" = 'repos/jubishop/podhaven/issues?state=all&per_page=100' ]; then
  printf '%s\n' '[[{"number":42,"labels":[{"name":"bug"}],"body":"<!-- sentry-feedback:podhaven:7485822944 -->\n<!-- analyze-sentry-feedback-findings:start -->\n<!-- analyze-sentry-feedback-findings:end -->"}]]'
  exit 0
fi
if [ "$1 $2" = 'issue edit' ]; then
  printf '%s\n' "$*" >> "$CHECK_SENTRY_TEST_CAPTURE/edit"
  exit 0
fi
if [ "$1 $2" = 'issue create' ]; then
  printf '%s\n' "$*" > "$CHECK_SENTRY_TEST_CAPTURE/create"
  printf '%s\n' 'https://github.com/jubishop/podhaven/issues/43'
  exit 0
fi
if [ "$1 $2" = 'issue comment' ]; then
  exit 0
fi
exit 97
EOF
chmod +x "$STUBS/gh"

PATH="$STUBS:$PATH" \
  SENTRY_BIN="$STUBS/sentry" \
  CHECK_SENTRY_TEST_CAPTURE="$CAPTURE" \
  RUNNER_TEMP="$TEST_DIR" \
  "$ROOT/bin/check-sentry-feedback" \
  > "$CAPTURE/output"

if ! grep -Fxq 'issue edit 42 --repo jubishop/podhaven --add-label sentry-feedback' "$CAPTURE/edit" 2>/dev/null; then
  echo "check-sentry-feedback did not label an already tracked feedback issue, or changed its priority" >&2
  exit 1
fi

if ! grep -Fq -- '--label sentry-feedback' "$CAPTURE/create" 2>/dev/null; then
  echo "check-sentry-feedback did not label a new feedback issue" >&2
  exit 1
fi

if ! grep -Fq -- '--label p2' "$CAPTURE/create" 2>/dev/null; then
  echo "check-sentry-feedback did not start a new feedback issue at p2" >&2
  exit 1
fi

rm -f "$CAPTURE/edit" "$CAPTURE/create"
PATH="$STUBS:$PATH" \
  SENTRY_BIN="$STUBS/sentry" \
  CHECK_SENTRY_TEST_CAPTURE="$CAPTURE" \
  RUNNER_TEMP="$TEST_DIR" \
  DRY_RUN=true \
  "$ROOT/bin/check-sentry-feedback" \
  > "$CAPTURE/dry-run-output"

if [[ -e "$CAPTURE/edit" || -e "$CAPTURE/create" ]]; then
  echo "check-sentry-feedback wrote to GitHub in a dry run" >&2
  exit 1
fi

if ! grep -Fxq 'Would create issue: Triage Sentry feedback PODHAVEN-3L (podhaven:7485822945) with labels sentry-feedback, p2' \
  "$CAPTURE/dry-run-output"; then
  echo "check-sentry-feedback did not show a new feedback issue's labels in a dry run" >&2
  exit 1
fi
