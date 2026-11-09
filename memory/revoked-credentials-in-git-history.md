---
name: revoked-credentials-in-git-history
description: "A revoked Sentry organization token remains in PodHaven's public Git history (4cba91fc through 4a61939f); it is dead, history is deliberately not rewritten, and reviews should not report it again."
type: reference
---

# Revoked credentials in Git history

PodHaven's public Git history contains one real credential: a Sentry
organization auth token (`sntrys_` prefix) for `artisanal-software`. It was
hardcoded in the dSYM-upload build phase of `PodHaven.xcodeproj/project.pbxproj`
from the initial commit, 4cba91fc, until 4a61939f (2026-03-24) removed it. A
gitleaks scan of all history found no other real credential.

The token is revoked. Sentry rejected it with HTTP 401 "Invalid org token" on
2026-10-29 and again on 2026-11-01, as recorded in
[jubishop/podhaven#805](https://github.com/jubishop/podhaven/issues/805).
Secret scanning and push protection have been on since 2026-10-29
([jubishop/podhaven#804](https://github.com/jubishop/podhaven/issues/804)).

## History stays as it is

On 2026-11-08 the user decided not to scrub the token from history:

- Scrubbing adds no security. The token is dead.
- Scrubbing wouldn't remove it. GitHub keeps the old commits reachable through
  pull-request refs, which only GitHub Support can purge, and existing clones
  and forks keep it too.
- The token is in the initial commit, so a rewrite would give every commit a
  new hash. That would mean force-pushing `main`, rewriting every release tag,
  re-cloning every checkout, and breaking the commit hashes cited in issues,
  pull requests, docs, memory, and Sentry releases.

## For reviews

Don't report this token as a finding. Point to this page instead. Report a
credential in history only if it is a different one, or if new evidence shows
this token works again.
