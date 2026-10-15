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

For the recovered AppHang scope gap and temporary callback, see
[recovered-hang diagnostic delivery](sentry-recovered-hang-diagnostics.md).

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

## MetricKit crash diagnostics

Sentry's MetricKit integration files hang, CPU-exception, and disk-write
diagnostics, but it skips `MXCrashDiagnostic`. Sentry's in-process crash
reporter is signal-based, so it cannot observe a watchdog or other `SIGKILL`
termination. `MetricKitMonitor` closes that gap. It keeps the local `.notice`
record of every diagnostic. It also sends each eligible crash diagnostic to
Sentry as one event when MetricKit delivers it, usually at the next launch.

| Diagnostic fields | Category | Reason |
| --- | --- | --- |
| Termination reason contains `watchdog`, `0x8badf00d`, or `2343432205` | `watchdog` | Watchdog kills arrive as `SIGKILL` |
| Exception type `EXC_RESOURCE` | `resource_limit` | Sentry does not handle this Mach exception |
| Exception type `EXC_GUARD` | `guard` | Sentry does not handle this Mach exception |
| Signal `SIGKILL` | `sigkill` | The signal cannot be caught |
| Anything else | Stays local | Sentry's handlers catch `SIGABRT`, `SIGBUS`, `SIGFPE`, `SIGILL`, `SIGPIPE`, `SIGSEGV`, `SIGSYS`, `SIGTRAP`, `SIGTERM`, and their Mach exceptions |

The event is fatal and unhandled. It uses the SDK's synthetic
`MXCrashDiagnostic` mechanism, including signal metadata. Each MetricKit call
stack becomes a thread that follows its most-sampled path from caller to
callee. The thread-attributed stack is the exception stack. Debug images carry
each binary UUID and the image address that MetricKit's offsets imply, so
Sentry symbolicates in-app frames with the uploaded dSYMs. The issue title is
the top symbolicated in-app function.

Attribution comes from the diagnostic, not the delivering process. The release
is `<bundle>@<version>+<build>`, `dist` is the build, and the `app` context's
version and build use the same values. The `metrickit_crash` context records
`termination`, `attribution=diagnostic_metadata`, the version, build, OS
version, architecture, device type, and bundle identifier. It also records
the payload's `periodStart` and `periodEnd`; the exception type and code, the
signal, and the termination reason when present; and thread, frame, and
attachment counts. Its `observation=delivery_launch` and `deliverySessionID`
identify the launch that sent it. That launch's scope also supplies the
`log-session-id` and `git-commit-hash` tags, the remaining app and device
context, and the recent-log attachments. Do not treat those as the terminated
process.

The fingerprint is `{{ default }}`, `metrickit-crash`, and the category. Sentry
groups by the symbolicated stack within each termination category, so
recurrences group across builds. Addresses, process IDs, timestamps, exception
codes, and termination text are not part of the key.

The event's size and quota use are bounded:

- At most five crash events are sent per payload; a warning counts the rest.
- At most 32 threads are kept, plus any thread-attributed stack beyond them.
- At most 128 frames are kept per thread, keeping the frames closest to the
  crash.
- Termination reasons are capped at 512 characters, and identity fields at 64.
- The raw `jsonRepresentation()` is attached as
  `metrickit-crash-diagnostic.json` when it is 256 KiB or smaller. Larger
  payloads report `rawPayloadAttachment=omitted_over_limit`.
- A payload with an Objective-C exception reason reports
  `omitted_exception_message` instead, because its message and arguments can
  hold runtime values.

The payload contains only call stacks, binary metadata, and termination
fields. An unreadable or empty call stack is logged as an error and not sent,
because the SDK would otherwise attach the delivering process's threads.
To symbolicate a downloaded attachment offline, pass it to the `analyze-logs`
skill's `symbolicate_metrickit.py`.

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

Run `bin/sentry-metrickit-smoke --device <available-iOS-Simulator-UDID>` with
authenticated Sentry CLI access to verify crash-diagnostic delivery. It builds
an isolated Simulator probe from the current sources and uploads the probe's
dSYM. The probe sends a synthetic watchdog diagnostic through
`MetricKitMonitor.receive(_:)` and the production Sentry configuration. The
diagnostic's frames are real function offsets in the probe binary, and its
version and build differ from the probe's own. The helper reads the event and
attachment back from Sentry. It checks symbolicated in-app frames, diagnostic
attribution, the exact bounded attachment, the context fields, and the absence
of user identity. It also symbolicates the downloaded attachment offline.
Evidence stays under ignored `.cache/sentry-metrickit-smoke/`. It never
installs on a physical device. Actual MetricKit delivery of a real watchdog
kill remains an observation limit.

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
