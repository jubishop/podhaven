#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-sentry-feedback-instructions.XXXXXX")"
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
  printf '%s\n' '[[{"number":42,"body":"<!-- sentry-feedback:podhaven:7485822944 -->"}]]'
  exit 0
fi
if [ "$1" = api ] && [ "$4" = 'repos/jubishop/podhaven/issues/42/comments?per_page=100' ]; then
  printf '%s\n' '[[]]'
  exit 0
fi
if [ "$1 $2" = 'issue comment' ]; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --body-file ]; then
      cp "$2" "$CHECK_SENTRY_TEST_CAPTURE/comment"
      exit 0
    fi
    shift
  done
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

if ! grep -Fq '<!-- sfeedback:podhaven:7485822944 -->' "$CAPTURE/comment"; then
  echo "check-sentry-feedback did not write the sfeedback deduplication marker" >&2
  exit 1
fi

if ! grep -Fq "\`bin/sfeedback podhaven:7485822944\`" "$CAPTURE/comment"; then
  echo "check-sentry-feedback did not provide the direct sfeedback command" >&2
  exit 1
fi
