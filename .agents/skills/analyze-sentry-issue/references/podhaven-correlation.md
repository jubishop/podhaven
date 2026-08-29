# PodHaven Sentry Correlation

Load only the sections relevant to the issue being diagnosed.

## Builds and known fixes

PodHaven releases use a value such as
`com.artisanalsoftware.PodHaven@1.0+498`. Build `NNN` normally maps to git tag
`v1.0bNNN`; prefer the event's `git-commit-hash` when present.

Search repository memory and closed GitHub issues for matching failures and
concrete fix commits. Use
`git merge-base --is-ancestor <fix-commit> <build-commit>` to determine whether
the failing build contains a suspected fix. A recurrence in a containing build
means the fix is incomplete.

## Attachments and NDJSON logs

List event attachments with
`.agents/scripts/sentry-cli/download_event_attachments.sh` before selecting any
downloads. With no `--name` or `--all`, the helper lists only. Download only
attachments that can affect the diagnosis and keep them inside the invocation's
temporary directory.

`log.ndjson` and `widget-log.ndjson` are the reporter's logs. Do not substitute
developer-local logs unless the event user is proven to be the same device.
Analyze downloaded NDJSON through `analyze-logs`. Identify the session that
contains the Sentry timestamp, keep later queries in that session, and begin
with the surrounding warnings and errors before widening the scope. Use the
same process for the widget log when widget behavior is plausible.

MetricKit diagnostics arrive on the launch after the incident, so their log
timestamp usually differs from the failure time. Search the whole attachment
by MetricKit category and use `analyze-logs` symbolication support rather than
limiting the first search to the Sentry timestamp.

## Targeted Sentry structured logs

Use PodHaven structured logs when a representative event has `user.id` or a
trace ID and the timeline can add evidence that attachments do not provide.
PodHaven error events often use `environment:testFlight`, while structured logs
usually use `environment:deployed`; do not copy the event environment into the
log query without first confirming it on log rows.

Prefer a `user.id` query, optionally narrowed by release. Fall back to the trace
ID when user correlation returns nothing. Choose a fetch period that covers the
event, write results to a dedicated directory under the invocation's temporary
directory, and use the shared Sentry-log scripts' help for their current
interfaces.

Start with a total window of `1200000` milliseconds centered on the event
(plus or minus 10 minutes). If it is too sparse, widen to `3600000` milliseconds
(plus or minus 30 minutes). A result far from the event time means correlation
failed. Report the correlation key, period, window, and relevant timeline in
Pacific Time.
