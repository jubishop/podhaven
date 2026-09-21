---
status: current
---

# Foreground termination diagnostics

PodHaven collects evidence automatically after an unexpected foreground exit.
The user must run the updated app and reopen it after the exit. Sentry can queue
reports until connectivity returns. MetricKit reports can arrive later. Neither
system guarantees a useful stack or an exact diagnosis for one termination.

## Recent history and attribution

The automatic attachments remain `recent-log.ndjson` and
`recent-widget-log.ndjson`. Their limits remain 128 KiB and 32 KiB, respectively.
Explicit feedback still attaches the full app and widget logs and any photos.

Each NDJSON record includes `sessionID`, `version`, `buildNumber`, and
`gitCommitHash`. The session ID is a random identifier for one process lifetime.
The app and widget have separate process identities. Rate-limit summaries carry
the same fields. Existing records from older builds can lack these fields; do
not infer their build or session from the process uploading them.

At the first recent-tail writer in a process, the writer retains complete prior
records up to half its trimming target. It removes incomplete trailing writes.
This bounded history remains in the file when current-process logging rolls
over. The remaining space holds current-process records. Full feedback logs
keep their existing rolling policy. Retention is bounded, so older records and
records too large for the available space can still be lost.

The app prepares and flushes its local logging before starting Sentry. This
makes the app tail available when the SDK reports a previous termination.
Sentry's initial scope includes `log-session-id`; the SDK can persist that tag
with the previous event. Match the event's tag to record `sessionID` values,
then check the record's build fields. Do not treat all attached records as one
session or use the uploading process's session as the terminated process.

Each allowed Sentry event includes `recent_log_files` context with the file
metadata status, observed byte count, and configured limit for each tail. This
contains no path or log contents. Its `observation=capture_time` and
`observationSessionID` identify the process inspecting the files, which can be
the next launch. A successful file-size check does not prove attachment
ingestion; compare this context with the event's downloadable attachments when
investigating another missing upload.

## MetricKit exit summaries

`MetricKitMonitor` receives foreground and background exit counts through
Apple's supported payload properties. Abnormal foreground counts, including
watchdog timeouts and memory-limit exits, produce a critical summary. Routine
foreground exits remain informational. Existing background severity decisions
and local diagnostic-payload capture are preserved.

The Sentry log transport forwards an explicit field list for these summaries:

| Fields | Meaning |
| --- | --- |
| `metricKit.kind=aggregate_exits`, `metricKit.scope` | Summary type and foreground/background category |
| `metricKit.periodStart`, `metricKit.periodEnd` | UTC reporting interval supplied by Apple |
| `metricKit.latestVersion`, `metricKit.payloadBuild` | Latest reported app version and available payload build; missing build is `unknown` |
| `metricKit.multipleVersions` | Whether the report spans app versions |
| `metricKit.attribution=reporting_period` | Counts describe an aggregate interval, not one event or session |
| `metricKit.appWatchdog`, `metricKit.memoryResourceLimit`, other named exit counters | Per-reason counts |

Version and period attributes are capped at 64 characters and counter attributes
at 32. Other event metadata, including raw MetricKit diagnostic JSON and media
URLs, is not added to Sentry Logs. Existing local diagnostic capture and the SDK's
native diagnostic handling remain separate.

The fixed `buildNumber`, `gitCommitHash`, and `logSessionID` log attributes
identify the reporting process. They do not override the payload's period or
build attribution. In particular, a multiple-version report cannot assign all
its counts to the latest build. See Apple's
[reporting-period attribution](https://developer.apple.com/documentation/metrickit/mxmetricpayload/includesmultipleapplicationversions).

## PODHAVEN-3J assessment

The cause of the build 573 termination remains unknown. The SDK's watchdog
classification and generic RAM wording do not establish an OS memory-limit
kill. Later recovered hangs and memory measurements describe another session.
They do not justify changes to accessibility text rendering or playback.

The first collection pass retains existing operation and lifecycle logs, adds
explicit session/build attribution, preserves prior history, and reports
foreground exit aggregates. File-availability context addresses the remaining
attachment-delivery gap. No continuous memory sampler or broad additional
debug upload is needed for this pass. A future report must establish the affected
session and build, retain the relevant operation timeline, and supply compatible
OS diagnostic evidence or aggregate exit counts before choosing a cause-specific
fix. Aggregate counts alone cannot identify the responsible application path.

## Verification boundaries

The September 21, 2026 audit verified actual Sentry ingestion and downloads for
a controlled ordinary event and a native crash sent after relaunch on My Mac.
The original attachment configuration delivered both synthetic NDJSON tails.
This proves the current SDK's controlled path, not why the build 573 event lacked
attachments. It does not prove the SDK's watchdog classifier identifies every
OS termination correctly.

The updated retention path also delivered both tails after 500 new-launch
records per file. Downloads contained 330 app records and 81 widget records,
retained the prior session and build fields, and totaled 159,051 bytes. A missing
widget tail did not block the event or app attachment. The remote foreground
summary retained watchdog and memory-limit counts, reporting dates, payload
version/build, multiple-version flag, and aggregate attribution.
Capture-time file context also reached Sentry with both files present and with
the widget file missing; it retained sizes and limits without paths or contents.

Regression coverage checks prior-history survival under new-launch log volume,
record boundaries and bounds, session/build fields, foreground and background
reporting, aggregate attribution, and the explicit remote field selection.
Controlled MetricKit summaries use synthetic platform payloads; actual Apple
delivery cadence and real-world recurrence remain observation limits.

TestFlight distribution, App Store privacy disclosure, and later quota checks
belong to the separate release workflow. They are not substituted by local
tests. Existing tracking is in [#644](https://github.com/jubishop/podhaven/issues/644)
and [#648](https://github.com/jubishop/podhaven/issues/648); the recurrence and
overall diagnostic decision belong to [#705](https://github.com/jubishop/podhaven/issues/705).
