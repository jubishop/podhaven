---
name: analyze-sentry-logs
description: >-
  Analyze PodHaven Sentry structured logs for real issues, severity mismatches,
  and missing observability. Use only when explicitly invoked.
user_invocable: true
disable-model-invocation: true
argument: Time span (such as 12h, 2d, or 1w) and an optional Sentry logs query
---

# Sentry Log Analysis

Analyze PodHaven's Sentry structured logs (`ourlogs`), using repository source
and history to explain them. Do not fetch Sentry issues, events, crashes, or
other Sentry data. Device NDJSON analysis belongs to `analyze-logs`; individual
error issues and feedback belong to `analyze-sentry-issue` and
`analyze-sentry-feedback`.

## Scope and access

Require a time span. If none is supplied, ask before fetching logs. Accept an
optional Sentry logs query. Default to warnings/errors unless the user
explicitly requests other levels. User, trace, and release filters preserve
that default. Express requested levels through a severity filter; use
`severity:*` for all levels.

PodHaven uses the device IDFV for `user.id`. Error events and structured logs
can have different environment tags. Do not copy an event's environment filter
without confirming it on log rows; prefer `user.id` and optional `release`.

Use the authenticated `sentry` CLI and the shared
[fetch helper](../../scripts/sentry-cli/fetch_sentry_logs.sh). If the CLI or
authentication is missing, stop and report it. Do not install tools or use the
Sentry MCP server.

From the repository root:

```bash
bash .agents/scripts/sentry-cli/fetch_sentry_logs.sh <time-span> \
  --out <unique-temporary-directory> --query '<optional-query>'
```

Omit `--query` when no filter is needed. Use a unique temporary directory for
each fetch and delete it after reporting.

## Coverage

Obtain complete counts for every matching pattern in the requested window.
The helper fixes the time window, follows all aggregate pages, and writes:

- `summary.json`: counts grouped by severity and full message.
- `detail.json`: up to 1,000 individual entries for investigation.
- `coverage.json`: effective query, fixed window, counts by severity, and
  separate aggregate/detail coverage states.

Check coverage before drawing conclusions. Individual entries can be a sample;
their count is not the total for the window. Obtain additional targeted samples
when needed to investigate patterns, using the same fixed window from
`coverage.json`. The helper also accepts a bounded ISO datetime range with
explicit timezone offsets for this purpose.

If a request or pagination fails, inspect the recorded coverage before using
the retained evidence. Resolve the failure and fetch more where possible. Disclose any
coverage that remains incomplete; do not claim full-window totals or complete
pattern coverage. Group message variants when they share a cause, while
preserving the counts and accounting for every returned group.

## Investigation

Trace each pattern far enough through source and logs to establish its trigger,
likely user impact, and whether it reflects expected behavior or a defect.
Choose the search method and amount of source context needed for that judgment.

Assess severity, available diagnostic context, and concrete nearby failure
paths that lack useful logging. Investigate bursts using timestamps and
available user/trace context before attributing them to duplicate work. For
`caughtError()` logs, inspect the current wrapper and `ErrorKit.isRemarkable`
implementation before recommending severity changes.

Mark a pattern **stale** only when release or repository-history evidence
establishes that its message or behavior was removed or replaced in the current
code. An unsuccessful source search is insufficient. Otherwise report **source
unresolved**, retain the observed impact, and explain the uncertainty. Stale
patterns still belong in the report.

Give each pattern one assessment of what the evidence establishes, including
**inconclusive** when needed. Keep that assessment separate from its supported
recommendations. A pattern can need a behavior fix, a severity change, and
better logging context together. Explain the expected benefit of each change;
do not infer missing observability from hypothetical failures.

## Report

Choose a concise layout that makes the findings easy to assess. Include:

- Requested scope, effective query, absolute time range in PST/PDT, coverage
  limits, and counts by severity.
- Every pattern's count, severity, source evidence or unresolved source,
  assessment, supporting reasoning, uncertainty, and recommendations.
- Concrete missing observability found during the investigation.

Distinguish observed behavior from inferred causes.
