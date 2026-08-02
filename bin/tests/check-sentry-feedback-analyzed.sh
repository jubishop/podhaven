#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-sentry-feedback-test.XXXXXX")"
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
  printf '%s\n' '{"data":[{"id":"7485822944","shortId":"PODHAVEN-3K","permalink":"https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A7485822944"}]}'
  exit 0
fi
exit 97
EOF
chmod +x "$STUBS/sentry"

cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
if [ "$1" = api ] && [ "$4" = 'repos/jubishop/podhaven/issues?state=all&per_page=100' ]; then
  printf '%s\n' '[[{"number":42,"body":"<!-- sentry-feedback:podhaven:7485822944 -->\n<!-- analyze-sentry-feedback-findings:start -->"}]]'
  exit 0
fi
printf '%s\n' "$*" >> "$CHECK_SENTRY_TEST_CAPTURE/forbidden"
exit 97
EOF
chmod +x "$STUBS/gh"

PATH="$STUBS:$PATH" \
  SENTRY_BIN="$STUBS/sentry" \
  CHECK_SENTRY_TEST_CAPTURE="$CAPTURE" \
  RUNNER_TEMP="$TEST_DIR" \
  "$ROOT/bin/check-sentry-feedback" \
  > "$CAPTURE/output"

if [[ -e "$CAPTURE/forbidden" ]]; then
  echo "check-sentry-feedback tried to add instructions to an analyzed issue" >&2
  exit 1
fi

if ! grep -Fq 'Already analyzed: podhaven:7485822944 in issue #42' "$CAPTURE/output"; then
  echo "check-sentry-feedback did not recognize the managed findings marker" >&2
  exit 1
fi
