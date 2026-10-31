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
over. The remaining space holds current-process records.

Each tail's per-record limit is a quarter of the current-process space left
beside a full prior history: 12 KiB for the app tail and 3 KiB for the widget
tail. A larger record, such as a raw MetricKit diagnostic, is written to the
tail as a stand-in. The stand-in keeps the record's level, timestamp, logger,
source location, session, and build fields. It also keeps a message prefix that
ends in `…` when shortened. Its metadata is replaced by
`fileLog.originalRecordBytes` and `fileLog.recordLimitBytes`.
One record therefore cannot evict the process's earlier records, such as its
launch timeline. Full feedback logs keep their existing rolling policy and
complete records, including raw MetricKit diagnostics. Retention is still
bounded, so older records can be lost to ordinary log volume.

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
Apple's supported payload properties. Abnormal counts, such as watchdog
timeouts, memory-limit exits, and bad-access crashes, produce an error summary.
Routine exits, including background memory-pressure jettisons, remain
informational. Local diagnostic-payload capture is preserved.

Each abnormal summary is also sent to Sentry as its own error event. Sentry
groups by in-app stack before message, and every summary is logged from the
same call site, so a message alone would put every exit kind in one issue. The
event's fingerprint is therefore `metrickit-exit`, the scope, and the nonzero
abnormal reasons in a stable order. Each scope and set of reasons gets its own
issue, and recurrences group whatever their counts. The `metrickit-exit` tag
holds the scope. The `metrickit_exit` context holds the summary's log
metadata: the `metricKit.*` fields below and the unprefixed per-reason counts.
The summary logs below `.critical`, so `CrashReportHandler` does not send a
second, stack-grouped event.

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
`MXCrashDiagnostic` mechanism, including signal metadata. MetricKit roots each
crash call stack at the crashing frame and nests each caller in `subFrames`.
Each call stack becomes a thread with that chain reversed into Sentry's
caller-to-callee order. The thread-attributed stack is the exception stack.
Debug images carry each binary UUID and the image address that MetricKit's
offsets imply, so Sentry symbolicates in-app frames with the uploaded dSYMs.
The issue title is the symbolicated in-app function closest to the crash.

Attribution comes from the diagnostic, not the delivering process. The release
is `<bundle>@<version>+<build>`, `dist` is the build, and the `app` context's
version and build use the same values. The `metrickit_crash` context records
`termination`, `attribution=diagnostic_metadata`, the version, build, OS
version, architecture, device type, bundle identifier, and the terminated
process's `pid`. It also records
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
  crash. `JSONDecoder` rejects documents nested more than 512 levels deep,
  and each caller adds two levels. Before decoding, the converter therefore
  prunes every caller after a stack's 129th frame. A deeper stack still keeps
  its 128 frames closest to the crash and counts in `truncatedThreads`; the
  attachment keeps the unpruned payload.
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

## Launch timeline

A watchdog kill during launch can lose the process's queued NDJSON records,
because the file writer runs at background QoS. In
[PODHAVEN-74](https://github.com/jubishop/podhaven/issues/815), only the
explicitly flushed first record reached disk. `LaunchTimeline` keeps a durable
record of each launch's phases instead.

Each launch maps one fixed 4 KiB file under `launch-timelines/` in the app's
documents directory. Its header holds the pid, the kernel's process start time,
the log session ID, version, build, git commit, and the milestone names in slot
order. Recording a milestone stores its wall-clock time in that slot, and only
the first occurrence counts. The mapping is shared, so the kernel keeps the
stores after a SIGKILL, and a milestone costs no write, encoding, or queue hop.
Creating the file costs a directory listing, a pruning pass, and one mapping,
once per launch. The directory keeps the newest `LaunchTimeline.capacity`
launches, counting the current one.

The milestones follow the launch path:

| Milestone | Recorded |
| --- | --- |
| `loggingStarted` | After swift-log is bootstrapped, before the first record opens the log files |
| `logsOpened`, `logsFlushed` | After that first record, then after the explicit pre-Sentry flush |
| `sentryStarted` | After `SentrySDK.start` returns |
| `databaseOpened` | After `initializeAppDB` opens and migrates the database |
| `backgroundTasksRegistered` | After every background task is registered |
| `audioConfigured` | After the synchronous audio session setup, or after scheduling its asynchronous retry when that setup fails |
| `bootstrapReturned` | At the end of `AppLauncher.bootstrap` |
| `firstScenePhase`, `firstScenePhaseHandled` | Around `PhoneSceneView`'s handling of its first scene phase |
| `siriCatalogPublicationStarted`, `siriCatalogPublicationFinished` | Around the launch Siri catalog publication on the database writer |

The logging and Sentry milestones are recorded only in deployed environments,
where `configureLogging` runs that path.

When `MetricKitMonitor` forwards an eligible crash diagnostic, it matches the
diagnostic's `pid` against the retained launches other than the current one. It
picks the latest launch with that pid that started by the diagnostic's end, so
a pid reused after a reboot or after the crash doesn't match. The event's
`launch_timeline` context then holds:

- `attribution`: `pid_match`, `not_retained`, or `unavailable` when the
  directory can't be listed. `not_retained` means no retained earlier launch
  has that pid. That launch may have run a build without launch timelines,
  been killed before its first milestone, failed to create its file, or been
  pruned.
- `pid`, `retainedLaunches`, and `unreadableLaunches`.
- For a match, the launch's `sessionID`, `appVersion`, `appBuild`,
  `gitCommitHash`, and `lastMilestone`.
- For a match, `millisecondsAfterOrigin` maps each reached milestone to its
  whole milliseconds after `origin`. The origin is the process start, or the
  first milestone when the start time was unavailable, and `originTimestamp`
  gives its time. Sentry returns fractional context numbers as strings, so the
  offsets are integers.

The `sessionID` matches the launch's NDJSON records. The context holds no
titles, URLs, user or device identifiers, or log contents.

Read a matched timeline against the termination reason's allowance:

- A late first milestone means time before PodHaven's code ran, such as pre-main
  loading.
- A late gap between milestones names the slow bootstrap step.
- A prompt `bootstrapReturned` with a late or missing `firstScenePhase` points
  at UIKit and SwiftUI scene setup.
- The Siri publication milestones show whether that publication overlapped the
  slow window.

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

On October 15, 2026, a one-off iOS Simulator probe checked oversized records.
It seeded near-cap prior history in both tails. It then logged launch records,
a 305 KiB raw MetricKit crash record from `MetricKitMonitor.diagnosticDirective`,
and one later record. Both downloaded tails kept the prior history, launch
records, a stand-in under 500 bytes, and the later record. Their sizes matched
the `recent_log_files` context.

Run `bin/sentry-metrickit-smoke --device <available-iOS-Simulator-UDID>` with
authenticated Sentry CLI access to verify crash-diagnostic delivery. It builds
an isolated Simulator probe from the current sources and uploads the probe's
dSYM. A first probe launch records launch-timeline milestones and flushes a
readiness record, and the helper then kills it with SIGKILL. A second launch
sends a synthetic watchdog diagnostic naming the killed launch's pid through
`MetricKitMonitor.receive(_:)` and the production Sentry configuration. The
diagnostic's frames are real function offsets in the probe binary, and its
version and build differ from the probe's own. The helper reads the event and
attachment back from Sentry. It checks symbolicated in-app frames in
caller-to-callee order, an issue title naming the crashing in-app function,
diagnostic attribution, the exact bounded attachment, the context fields, and
the absence of user identity. It also checks that `launch_timeline` matched the
killed launch's pid, session, and own build, and that its milestones survived
the kill in order. It then symbolicates the downloaded attachment offline.
Evidence stays under ignored `.cache/sentry-metrickit-smoke/`, within the
[smoke evidence bound](sentry-recovered-hang-diagnostics.md#controlled-ios-verification).
It never installs on a physical device. Actual MetricKit delivery of a real watchdog
kill remains an observation limit.

Regression coverage checks prior-history survival under new-launch log volume,
oversized-record stand-ins in both configured tails, complete oversized records
in the full rolling log, record boundaries and bounds, session/build fields,
foreground and background reporting, aggregate attribution, and the explicit
remote field selection.
Controlled MetricKit summaries use synthetic platform payloads; actual Apple
delivery cadence and real-world recurrence remain observation limits.

TestFlight distribution, App Store privacy disclosure, and later quota checks
belong to the separate release workflow. They are not substituted by local
tests. Existing tracking is in [#644](https://github.com/jubishop/podhaven/issues/644)
and [#648](https://github.com/jubishop/podhaven/issues/648); the recurrence and
overall diagnostic decision belong to [#705](https://github.com/jubishop/podhaven/issues/705).
