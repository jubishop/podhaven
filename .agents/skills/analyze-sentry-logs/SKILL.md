---
name: analyze-sentry-logs
description: >-
  Analyze PodHaven Sentry structured logs for real issues, severity mismatches,
  and missing observability. Use only when explicitly invoked.
disable-model-invocation: true
argument-hint: "<time-span, such as 2d> [logs-query]"
---

# Sentry Log Analysis

Analyze PodHaven's Sentry structured logs (`ourlogs`) over a time span, using
repository source and history to explain them. Do not fetch Sentry issues,
events, crashes, or other Sentry data. Device NDJSON analysis belongs to
`analyze-logs`; individual error issues and feedback belong to
`analyze-sentry-issue` and `analyze-sentry-feedback`.

## Scope and access

The arguments are a required time span, such as `12h`, `2d`, or `1w`, and an
optional Sentry logs query. If no span is given, ask for one before fetching.
Analyze warnings and errors unless the user asks for other levels.

Fetch with the authenticated `sentry` CLI through the shared
[fetch helper](../../scripts/sentry-cli/fetch_sentry_logs.sh). Its `--help`
gives the periods, query defaults, outputs, and coverage states, and why to
filter by `user.id` or `release` rather than `environment`. If the CLI or
authentication is missing, stop and report it; do not install tools or use the
Sentry MCP server. Give each fetch its own empty temporary directory and
delete it after reporting.

## Coverage

Report complete counts for every matching pattern in the window, and check
`coverage.json` before drawing conclusions. Detail entries can be a sample, so
their count is not the window's total; fetch targeted samples within the same
fixed window when a pattern needs more.

If a request or pagination fails, resolve it and fetch again where possible.
Disclose any coverage that remains incomplete, and claim no full-window totals
or complete pattern coverage then. Group message variants that share a cause
while preserving their counts and accounting for every returned group.

## Investigation

Trace each pattern through source and logs far enough to establish its
trigger, likely user impact, and whether it reflects expected behavior or a
defect.

Check each pattern's history before assessing it: fetch the open and closed
GitHub issues labeled `sentry-issue` or `sentry-feedback` once, and search
memory. Cite a matching issue or note, and keep its settled disposition, such
as an error accepted as noise, unless new evidence contradicts it; say what
changed when it does.

Assess severity, diagnostic context, and concrete nearby failure paths that
lack useful logging. Investigate bursts by timestamp and user or trace context
before attributing them to duplicate work. For `caughtError()` logs, read the
current wrapper and `ErrorKit.isRemarkable` before recommending severity
changes.

Mark a pattern **stale** only when release or repository history shows its
message or behavior was removed or replaced in the current code; a failed
source search is not enough. Otherwise report **source unresolved**, keep its
observed impact, and explain the uncertainty. Stale patterns stay in the
report.

Give each pattern one assessment of what the evidence establishes, which may
be **inconclusive**, kept separate from its recommendations. A pattern can need
a behavior fix, a severity change, and better logging context together. Give
each change's expected benefit, and infer no missing observability from
hypothetical failures.

## Report

Choose a concise layout that makes the findings easy to assess. Include:

- Requested scope, effective query, absolute time range, coverage limits, and
  counts by severity.
- Every pattern's count, severity, source evidence or unresolved source,
  assessment, reasoning, uncertainty, and recommendations.
- Concrete missing observability found during the investigation.

Distinguish observed behavior from inferred causes.
