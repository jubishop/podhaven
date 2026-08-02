#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sfeedback-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

STUBS="$TEST_DIR/bin"
CAPTURE="$TEST_DIR/capture"
mkdir -p "$STUBS" "$CAPTURE"

for command_name in ghcw llm sentry; do
  stub="$STUBS/$command_name"
  printf '%s\n' \
    '#!/bin/sh' \
    "printf '%s\\n' \"\$0\" >> \"\$SFEEDBACK_TEST_CAPTURE/forbidden\"" \
    'exit 97' \
    > "$stub"
  chmod +x "$stub"
done

cat > "$STUBS/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$PWD" > "$SFEEDBACK_TEST_CAPTURE/pwd"
printf '%s\n' "$@" > "$SFEEDBACK_TEST_CAPTURE/args"
EOF
chmod +x "$STUBS/codex"

(
  cd "$ROOT/PodHavenTests"
  PATH="$STUBS:$PATH" \
    SFEEDBACK_TEST_CAPTURE="$CAPTURE" \
    "$ROOT/bin/sfeedback" podhaven:7485822944
)

if [[ -e "$CAPTURE/forbidden" ]]; then
  echo "sfeedback invoked a removed worktree-preparation dependency" >&2
  exit 1
fi

if [[ "$(< "$CAPTURE/pwd")" != "$ROOT" ]]; then
  echo "sfeedback did not launch Codex from the repository root" >&2
  exit 1
fi

EXPECTED_ARGS="$TEST_DIR/expected-args"
printf '%s\n' \
  '--dangerously-bypass-approvals-and-sandbox' \
  "\$analyze-sentry-feedback podhaven:7485822944" \
  > "$EXPECTED_ARGS"

if ! cmp -s "$EXPECTED_ARGS" "$CAPTURE/args"; then
  echo "sfeedback launched Codex with unexpected arguments" >&2
  diff -u "$EXPECTED_ARGS" "$CAPTURE/args" >&2 || true
  exit 1
fi

printf '%s\n' \
  '#!/bin/sh' \
  "printf '%s\\n' '{\"data\":[{\"id\":\"7485822944\",\"shortId\":\"PODHAVEN-3K\",\"metadata\":{\"message\":\"Playback stopped\",\"contact_email\":\"reporter@example.com\"},\"permalink\":\"https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A7485822944\"}],\"hasMore\":false}'" \
  > "$STUBS/sentry"
chmod +x "$STUBS/sentry"

printf '%s\n' \
  '#!/bin/sh' \
  "printf '%s\\n' '[[{\"number\":99,\"state\":\"open\",\"body\":\"https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A7485822944\\n<!-- analyze-sentry-feedback-findings:start -->\\n<!-- analyze-sentry-feedback-findings:end -->\"},{\"number\":42,\"state\":\"open\",\"body\":\"<!-- sentry-feedback:podhaven:7485822944 -->\\n<!-- analyze-sentry-feedback-findings:start -->\"}]]'" \
  > "$STUBS/gh"
chmod +x "$STUBS/gh"

cat > "$STUBS/fzf" <<'EOF'
#!/bin/sh
first=true
while IFS= read -r line; do
  printf '%s\n' "$line" >> "$SFEEDBACK_TEST_CAPTURE/picker"
  if "$first"; then
    selection="$line"
    first=false
  fi
done
printf '%s\n' "$selection"
EOF
chmod +x "$STUBS/fzf"

rm -f "$CAPTURE/args" "$CAPTURE/pwd"
(
  cd "$ROOT/PodHavenTests"
  PATH="$STUBS:$PATH" \
    SFEEDBACK_TEST_CAPTURE="$CAPTURE" \
    "$ROOT/bin/sfeedback"
)

if ! grep -Fq 'GitHub: #42 intake' "$CAPTURE/picker"; then
  echo "sfeedback did not prefer the exact-marker issue or require a complete findings block" >&2
  exit 1
fi

if ! cmp -s "$EXPECTED_ARGS" "$CAPTURE/args"; then
  echo "sfeedback did not launch the selected feedback" >&2
  diff -u "$EXPECTED_ARGS" "$CAPTURE/args" >&2 || true
  exit 1
fi

printf '%s\n' \
  '#!/bin/sh' \
  "printf '%s\\n' '[[{\"number\":42,\"state\":\"open\",\"body\":\"<!-- sentry-feedback:podhaven:7485822944 -->\\n<!-- analyze-sentry-feedback-findings:start -->\\n<!-- analyze-sentry-feedback-findings:end -->\"}]]'" \
  > "$STUBS/gh"
chmod +x "$STUBS/gh"

rm -f "$CAPTURE/args" "$CAPTURE/pwd" "$CAPTURE/picker"
(
  cd "$ROOT/PodHavenTests"
  PATH="$STUBS:$PATH" \
    SFEEDBACK_TEST_CAPTURE="$CAPTURE" \
    "$ROOT/bin/sfeedback"
)

if ! grep -Fq 'GitHub: #42 analyzed' "$CAPTURE/picker"; then
  echo "sfeedback did not recognize a complete findings block as analyzed" >&2
  exit 1
fi

if ! cmp -s "$EXPECTED_ARGS" "$CAPTURE/args"; then
  echo "sfeedback did not launch the fully analyzed feedback" >&2
  diff -u "$EXPECTED_ARGS" "$CAPTURE/args" >&2 || true
  exit 1
fi
