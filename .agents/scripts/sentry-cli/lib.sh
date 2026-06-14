#!/bin/bash
# PodHaven Sentry skill helpers — wraps the `sentry` CLI (cli.sentry.dev).
# Auth: existing ~/.sentryclirc token or SENTRY_AUTH_TOKEN (sentry auth login).
# Install (user-managed): curl https://cli.sentry.dev/install -fsS | bash
# Optional fish completions (home dir only): sentry cli setup

SENTRY_ORG="${SENTRY_ORG:-artisanal-software}"
SENTRY_PROJECT="${SENTRY_PROJECT:-podhaven}"
SENTRY_TARGET="${SENTRY_ORG}/${SENTRY_PROJECT}"

_sentry_bin() {
  if [[ -n "${SENTRY_BIN:-}" ]]; then
    echo "${SENTRY_BIN}"
    return 0
  fi
  if command -v sentry >/dev/null 2>&1; then
    command -v sentry
    return 0
  fi
  echo "npx"
}

sentry_cmd() {
  local bin
  bin="$(_sentry_bin)"
  if [[ "$bin" == "npx" ]]; then
    npx --yes sentry@latest "$@"
  else
    "$bin" "$@"
  fi
}

require_sentry_auth() {
  if ! sentry_cmd auth status >/dev/null 2>&1; then
    echo "Error: Sentry auth required. Run: sentry auth login" >&2
    echo "  (or set SENTRY_AUTH_TOKEN / ~/.sentryclirc from a prior login)" >&2
    return 1
  fi
}
