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

## Notice policy

Exceptional events log at `.notice` and normal events at `.info`. Both stay in
local logs (OSLog, the NDJSON file logs, and the recent-log attachments on
Sentry events and feedback) and stay below the `.warning` level that reaches
Sentry Logs. They logged at `.warning` until the
[real-world assessment](#real-world-assessment) found no case for pacing. The
`suppressedWarnings` and `warningSuppressed` fields keep their names and count
suppressed notices.

The long-run threshold is **20 seconds**.
For silence, this measures one uninterrupted foreground or background drain,
including all files in that drain. It is a telemetry convention, not a measured
performance limit or an iOS deadline. Apple permits processing tasks to run for
minutes but can interrupt them; the expiration handler requests prompt cleanup.
See [BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)
and [expirationHandler](https://developer.apple.com/documentation/backgroundtasks/bgtask/expirationhandler).

- `silenceRunSlow`: one notice when a run first reaches the threshold. Progress
  checkpoints can emit this before the current file finishes or publishes a map.
- `silenceRunFinished`: a terminal notice for a long run, a thermal interruption
  that discards audio already processed, or the third and subsequent expirations
  of the same content generation within the aggregation window.
- Fast completion, isolated short expiration, lifecycle cancellation, and lost
  eligibility stay at info, as do per-file attempt events. Existing
  decoding/database error logs retain their error handling and severity.

The diagnostics allow at most two notices per run and six notices in each
15-minute window, measured with a monotonic clock. Excess notices become info
summaries and increment the suppressed counter. These are bounds on exceptional
telemetry, not limits on analysis work.

Expiration history retains at most 64 content generations, uses a fixed window starting at the first expiration for that generation,
and resets that entry after 15 minutes. All history resets on process launch. Counts describe a bounded observation
window; they are not a complete restart history. Stable content generation IDs
allow a later agent to correlate observations from different process sessions.

## Reading events

All decision fields are in the message text. Read them from local logs or a
feedback log attachment; these events no longer reach Sentry Logs.

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

## Real-world assessment

Assessed on 2026-10-14 from every `silenceRunSlow` and `silenceRunFinished`
warning in Sentry Logs: 146 events from 2026-09-15 to 2026-10-14. They came
from builds 577 through 586, in the TestFlight environment only, from two
devices and 97 runs (82 background, 15 foreground). Every build included the
task-priority change, and every event reported `taskPriority=9`, so no
before-and-after priority comparison was possible. The silence code was the
same in all of these builds.

| Terminal group | Runs | Median wall | Audio processed | Discarded |
| --- | --- | --- | --- | --- |
| Background, completed | 28 | 75s | 87.1h | 0.1% |
| Background, expired | 10 | 108s | 59.2h | 10.4% |
| Foreground, completed | 4 | 32s | 13.2h | 0% |
| Foreground, interrupted by backgrounding | 9 | 38s | 17.4h | 36.7% |
| No file attempted | 40 | 39s | 0 | 0 |

- **Lost work** came from long files (35–117 minutes) interrupted mid-attempt.
  Background expiration and leaving the app lost similar amounts. No content
  generation expired three times within the aggregation window.
- **Thermal pressure** stayed nominal or fair and never stopped or deferred a
  run.
- **Concurrent embedding or transcription work** did not coincide with slower
  runs.
- **44% of terminal warnings were runs with no file to analyze.** Their wall
  time was mostly waiting (median process CPU 2.15s), and `ContinuousClock`
  includes time while the process is suspended.
- **Session counters** show these warnings covered about 35% of runs. Six slow
  runs never reported a terminal event; the data cannot tell process
  termination from lost delivery.

Pacing is unsupported by the observed runs. Longer attempts would likely
increase expirations, restarts, and discarded audio. The sample covers two
TestFlight devices and only runs that crossed the warning level, so it does not
represent all users. No CPU or energy figure is attributable to silence analysis
alone.

Because the warnings answered the question they were added for, the events now
log below Sentry's level as described in the [notice policy](#notice-policy).

## Playback cut records

Each automatic cut that completes for the current item logs one `.info`
`event=silenceCut` record from `PodAVPlayer.shortenSilenceIfNeeded()`. It stays
out of Sentry Logs. In-app feedback carries it in the attached `log.ndjson`;
other Sentry events carry it only while it remains in the smaller
`recent-log.ndjson` tail. It helps explain why a cut sounded like a skip:
clipped speech, a dropout during the seek, or a retained pause that is too
short.

| Field | Meaning |
| --- | --- |
| `episodeID`, `playerGeneration` | Episode and player item that made the cut |
| `mode`, `protection`, `rate` | Effective preset, quiet audio protection, and selected playback rate |
| `intervalStart`, `intervalEnd` | Source bounds of the quiet interval being shortened |
| `from`, `target`, `actual` | Position when the seek was requested, the requested landing, and the landing the player reports |
| `removedSeconds` | Source audio skipped: `actual` minus `from` |
| `completed`, `seekMs` | Whether the seek completed, and monotonic time from the request to its completion handler |
| `routeOutputs`, `outputLatencyMs`, `ioBufferMs` | Audio session output ports, output latency, and I/O buffer duration when the seek was requested |

Positions are source seconds. `seekMs` excludes the later hop to the main actor
and the position save. Output latency is the audio session's report; it does
not show whether `AVPlayer` already compensates for it.
