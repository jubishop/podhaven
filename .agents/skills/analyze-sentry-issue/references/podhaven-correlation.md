# PodHaven Sentry Correlation

## Builds and known fixes

Release `com.artisanalsoftware.PodHaven@<version>+<build>` maps to git tag
`v<version>b<build>`, such as `v1.7.1b595`; prefer the event's
`git-commit-hash` when present. A MetricKit event takes that tag, and for
Sentry's own MetricKit events its release too, from the later launch that sent
it, so take its build from the diagnostic's metadata: the `metrickit_crash`
context or the raw payload attachment.

Test whether the failing build contains each fix the tracking review found with
`git merge-base --is-ancestor <fix-commit> <build-commit>`. A recurrence in a
containing build means the fix is incomplete.

## Attachments and NDJSON logs

List an event's attachments with
`.agents/scripts/sentry-cli/download_event_attachments.sh`, then download only
those that can affect the diagnosis. Analyze only a download that completed,
never filling its gaps from an earlier attempt.

Every PodHaven event attaches the reporter's bounded `recent-log.ndjson` and
`recent-widget-log.ndjson`. Do not substitute developer-local logs unless the
event user is proven to be the same device. Analyze the logs through
`analyze-logs`, starting with the warnings and errors around the Sentry
timestamp in the launch whose `sessionID` is the event's `log-session-id` tag,
and add the widget log when widget behavior is plausible.

MetricKit diagnostics arrive on the launch after the incident, which is the
launch a MetricKit event's `log-session-id` names. A `metrickit_crash` event
whose `launch_timeline` context has `attribution` `pid_match` names the failing
launch's `sessionID` and `gitCommitHash`; otherwise look for that launch among
the attachment's earlier launches by the diagnostic's build and period. Search
the whole attachment by the `MetricKit` category rather than only around the
Sentry timestamp.

## Targeted Sentry structured logs

Use PodHaven structured logs when a representative event has `user.id` or a
trace ID and the timeline can add evidence that attachments do not provide.
Fetch them by `user.id` with `.agents/scripts/sentry-cli/fetch_sentry_logs.sh`,
falling back to the trace ID when that returns nothing; its help says why not
to query by the event's environment. Filter them to a window centered on the
event with
`.agents/scripts/sentry-cli/filter_sentry_logs.py`, widening a sparse window
to about half an hour each side. A result far from the event time means
correlation failed. Report the correlation key, period, window, and relevant
timeline in Pacific Time.
