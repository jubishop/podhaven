---
name: "sentry-cli-response-cache"
description: "The sentry CLI caches GET responses on this machine for up to five minutes, so tooling that reads Sentry state after writing it must bypass the cache with --fresh or SENTRY_NO_CACHE=1."
type: "reference"
---

# Sentry CLI response cache

The `sentry` CLI from cli.sentry.dev caches GET responses locally. Endpoints
it doesn't classify, including `files/dsyms/` and releases, fall into its
"stable" tier, which it serves from the cache for 5 minutes. `sentry api` has
no `--fresh` flag. `SENTRY_NO_CACHE=1`, exactly `1`, turns the cache off for
every command.

On November 4, 2026, UTC, with CLI 0.45.0, `sentry release set-commits
--clear` changed two releases. A plain `sentry api` read of one of them then
returned the release from before the write until the cached copy expired,
with an `age` header that reached 243 seconds. A cache-busted query and a direct `curl` to
the API returned the new state.

Tooling that reads Sentry state it or another step just wrote must bypass the
cache:

- Commands that take `--fresh`, such as `sentry issue list`, `sentry issue
  view`, and `sentry explore`, pass it.
- `sentry api` reads, and scripts with several Sentry calls, run with
  `SENTRY_NO_CACHE=1`. `bin/deploy.sh` exports it before its first Sentry
  call.
