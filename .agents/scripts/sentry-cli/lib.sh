#!/bin/bash
# PodHaven Sentry skill helpers — wraps the `sentry` CLI (cli.sentry.dev).
# Auth: existing ~/.sentryclirc token or SENTRY_AUTH_TOKEN (sentry auth login).

SENTRY_ORG="artisanal-software"
SENTRY_PROJECT="podhaven"
# shellcheck disable=SC2034
SENTRY_TARGET="${SENTRY_ORG}/${SENTRY_PROJECT}"

sentry_bin() {
  local bin
  if [[ -n "${SENTRY_BIN:-}" ]]; then
    bin="${SENTRY_BIN}"
  elif command -v sentry >/dev/null 2>&1; then
    bin="$(command -v sentry)"
  else
    echo "Error: the sentry CLI is required on PATH." >&2
    echo "  Install it from https://cli.sentry.dev, then run: sentry auth login" >&2
    return 127
  fi
  echo "$bin"
}

sentry_cmd() {
  local bin
  bin="$(sentry_bin)" || return
  "$bin" "$@"
}

require_sentry_auth() {
  local bin
  bin="$(sentry_bin)" || return
  if ! "$bin" auth status >/dev/null 2>&1; then
    echo "Error: Sentry auth required. Run: sentry auth login" >&2
    echo "  (or set SENTRY_AUTH_TOKEN / ~/.sentryclirc from a prior login)" >&2
    return 1
  fi
}
