---
status: current
---

# Silence analysis diagnostics

These diagnostics collect evidence about sustained silence analysis and work lost
when a background grant expires. Task priorities, scheduling, thermal policy,
decoding, silence maps, and playback retain their existing behavior. Before
publishing a completed scan, the processor reconciles current eligibility and
thermal state so delayed settings or thermal observations do not bypass the
cancellation check.

## Warning policy

The initial long-run threshold is **20 seconds**, matching embedding computation.
For silence, this measures one uninterrupted foreground or background drain,
including all files in that drain. It is a telemetry convention, not a measured
performance limit or an iOS deadline. Apple permits processing tasks to run for
minutes but can interrupt them; the expiration handler requests prompt cleanup.
See [BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)
and [expirationHandler](https://developer.apple.com/documentation/backgroundtasks/bgtask/expirationhandler).

- `silenceRunSlow`: one warning when a run first reaches the threshold. Progress
  checkpoints can emit this before the current file finishes or publishes a map.
- `silenceRunFinished`: a terminal warning for a long run, a thermal interruption
  that discards audio already processed, or the third and subsequent expirations
  of the same content generation within the aggregation window.
- Fast completion, isolated short expiration, lifecycle cancellation, and lost
  eligibility remain below warning. Per-file attempt events also stay local.
  Existing decoding/database error logs retain their error handling and severity.

New diagnostics allow at most two warnings per run and six warnings in each
15-minute window, measured with a monotonic clock. Excess warnings become local
info summaries and increment a suppressed-warning counter. These are additional
bounds on exceptional telemetry, not limits on analysis work.

Expiration history retains at most 64 content generations, uses a fixed window starting at the first expiration for that generation,
and resets that entry after 15 minutes. All history resets on process launch. Counts describe a bounded observation
window; they are not a complete restart history. Stable content generation IDs
allow a later agent to correlate observations from different process sessions.

## Reading events

All decision fields are in the message text. `SentryLogHandler` forwards that
text and its existing build, version, and commit attributes. No change to the
global warning-level Sentry filter or arbitrary logger metadata is needed.

| Field | Meaning |
| --- | --- |
| `sessionID`, `runID`, `attemptID` | Process-local diagnostics session, drain, and per-file attempt |
| `generation`, `file` | Cached content identity and existing cached filename |
| `mode`, `taskPriority` | Foreground/background launch mode and observed Swift task priority |
| `wallSeconds`, `attemptWallSeconds` | Elapsed run and current/last attempt time |
| `processedAudioSeconds` | Audio processed across the run, including discarded attempts |
| `attemptAudioSeconds`, `totalAudioSeconds` | Current/last file progress and asset duration; unknown until loaded |
| `completedFiles`, `publishedFiles`, `failedFiles` | Completed scans, published maps, and failed attempts |
| `discardedAudioSeconds` | Processed audio whose result was not published, including interruption and stale publication |
| `outcome`, `stopReason`, `backgroundExpired` | Run result, observed cancellation/deferral reason, and independent OS-expiration flag |
| `thermal`, `startThermal` | Current and initial thermal pressure |
| `transcriptionActive`, `embeddingActive` | Whether those workers currently own work |
| `transcriptionObserved`, `embeddingObserved` | Whether concurrent ownership was seen at a checkpoint in this run |
| `processCPUSeconds` | Change in whole-process user plus system CPU time; explicitly unavailable on sampling failure |
| `expirationCount`, `expirationDiscardedSeconds`, `previousExpiredRunID` | Bounded same-generation expiration history and lost work |
| `sessionRuns`, `sessionCompletedRuns`, `sessionInterruptedRuns`, `sessionExpirations` | Cumulative counts for this diagnostics session |
| `sessionBackgroundRuns`, `sessionBackgroundCompletedRuns` | Background-only denominators within this session |
| `sessionPublishedFiles`, `sessionDiscardedAudioSeconds`, `suppressedWarnings` | Cumulative publication, discarded work, and suppressed-warning counts |

Overlapping cancellation signals can occur. `stopReason` preserves the first
reason recorded by the app; `backgroundExpired` independently records OS
expiration, even when an app cancellation was already recorded.

Worker ownership is context, not proof that a worker consumed CPU throughout an
interval. CPU time includes all app threads, database work, playback, and other
workers. It can exceed elapsed time on multiple cores. It cannot attribute heat,
energy consumption, or CPU time specifically to silence analysis. No per-worker
CPU or energy measurement is available from these events.

## Cost and interruption limits

Progress is updated after decoded buffers without per-buffer log output. Timing
and concurrent-work checks occur at most once per processed audio second, plus
attempt/run boundaries. There are no polling tasks or periodic timers. A slow
event therefore needs a progress or boundary checkpoint; a blocked decoder or
abruptly terminated process may never emit it or the terminal summary.

CPU samples use
[`getrusage(RUSAGE_SELF)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html)
at run start and summary emission, never per buffer. A development-host probe
measured 10,000 calls in about 3.6 ms with no failures. This is an API overhead
check on the Mac, not a device benchmark or an energy measurement.

No new persisted cache or database state is added. Session counters and rate
limits reset on relaunch. A final log and its network delivery cannot be
guaranteed after an abrupt process termination. An expiration callback means
iOS asked this grant to stop; it does not prove the process was killed.

## Later real-world assessment

The user will trigger a separate agent after the telemetry has run in the wild.
Physical-device calibration and live Sentry delivery are not PR delivery gates.

1. Record the deployed build, commit, environment, and observed task priority.
   Account for the separate task-priority change when comparing builds.
2. Find `event=silenceRunSlow` and `event=silenceRunFinished` in Sentry logs.
   Verify that warning events contain the fields above. Use local logs or a
   feedback log attachment to inspect routine attempts and lower-severity runs.
3. Group by session and run. Pair the early snapshot with its terminal result.
   Group by content generation to inspect restart cost across attempts/launches.
4. Compare completed runs with expired runs, audio processed versus discarded,
   thermal state, and concurrent work. Separate foreground and background runs.
5. Use cumulative counters carefully: take differences within the same session,
   not sums of cumulative values. Events omitted by rate limits and sessions
   without warnings are not a representative sample of all users or all work.
6. Report whether pacing is warranted, unsupported by the observed runs, or
   still uncertain. Record unavailable data. If proposing pacing, explain both
   its intended benefit and the risk of more expirations/restarts. Revisit the
   initial threshold only with supporting evidence.

Local regression tests establish message contents, severity, and bounds. They do
not establish successful network delivery to Sentry or a need for pacing.
