---
status: current
---

# File logging cost and admission

The logging investigation in [#725](https://github.com/jubishop/podhaven/issues/725)
found avoidable caller blocking in ordinary background file logging. The
measurements below support moving that work off the caller and bounding pending
records. They do not establish that logging caused the reported multi-second
episode-transition delay. The complete playback diagnosis remains in
[#727](https://github.com/jubishop/podhaven/issues/727).

## Equal-work comparison

On October 2, 2026, an isolated Debug run on an Apple M5 Pro, macOS 27.0.1,
Xcode 27.0 (27A266a), compared seven repetitions per policy. The source included
the mapped chart store from PR #730 and the admission/order changes on the
`measureLoggingOverhead` branch. Only the suppression-summary wording changed
between this measurement and commit `d472944a`.

Each repetition emitted 100 synthetic debug records from ten call sites to
both production-sized file sinks. The recent sink used previous-session
retention. Both policies used the same admission code, payloads, metadata
provider, file sizes, and empty initial files. Policy order alternated between
repetitions. All 200 file records survived every repetition, totaling 83,780
bytes. No truncation or admission loss explains the difference.

| Measurement | Synchronous writes | Asynchronous writes |
| --- | ---: | ---: |
| Median caller time, 100 calls / two sinks | 6.577 ms | 0.602 ms |
| Caller-time range across seven repetitions | 6.499–7.020 ms | 0.577–0.612 ms |
| Median within-run p95 call | 71.125 μs | 8.250 μs |
| Median within-run p99 call | 368.958 μs | 17.667 μs |
| Median final flush time | 0.110 ms | 7.748 ms |
| Median process CPU through final flush | 6.790 ms | 15.882 ms |

The caller returned about 91% sooner. The asynchronous worker still did the
I/O, and measured total process CPU increased. This is a caller-blocking
improvement, not a CPU-saving claim. CPU samples include the probe's metadata
counter, queue scheduling, and other process work. They are not device energy
measurements. These runs used a Swift Testing caller, not audible playback.

`FileLogCostTests` preserves this comparison and checks that both policies keep
the same complete burst. Run that suite alone with the repository's
[focused Swift test procedure](../development-workflow.md#current-revision-swift-validation).
Do not use timings from the concurrent full suite for comparison. The isolated
result and raw-log gate passed with zero skipped tests and no diagnostics.
Local evidence is under `.cache/logging-725/production-file-micro*`.

## Component and overload measurements

A separate isolated probe ran seven repetitions of 1,000 attempts per mode on
the same host and source. The file stress cases used a 64 KiB maximum and
48 KiB target, deliberately stressing rotation rather than estimating a normal
playback transition. Values below are medians across repetitions.

| Component / workload | Caller time per 1,000 attempts | What the number includes |
| --- | ---: | --- |
| Sentry warning adapter with fake SDK sink | 59.029 ms | Attribute construction and fake storage; excludes the real SDK, encoding, and upload |
| Synchronous file, distinct sites | 56.106 ms | All 1,000 entries constructed; encoding, writes, and rotation |
| Mapped chart capture, changing inputs | 8.742 ms | Snapshot construction and mapped capture; eight recent states retained |
| Synchronous file, one repeated site | 3.909 ms | 50 entries constructed; 950 attempts rejected |
| Asynchronous file, distinct-site flood | 3.330 ms | Median 293 entries constructed; the rest rejected before metadata/encoding/queueing |
| Asynchronous file, one repeated site | 2.983 ms | 50 entries constructed; 950 attempts rejected |
| OSLog adapter | 0.549 ms | Submission only; excludes downstream unified-log processing |

The distinct-site asynchronous case is not equal work to the synchronous case.
Its purpose is to inspect overload behavior. Admission limited pending ordinary
records to 256; the worker could finish some records while the producer was
still submitting. The final flush took a median 27.784 ms and process CPU
through the flush was 34.337 ms. Suppression summaries also consume output
space; admission does not eliminate all later accounting work.

For the mapped chart case, exporting the retained history separately took a
median 1.855 ms and produced 7,853 bytes. Export happens during event
preparation, outside the rendering path. The integrated chart tests also
compare capture with the former journal; see
[chart diagnostics](../chart-progress-diagnostics.md#cost-measurement).

The isolated component probe passed its result/raw-log checks. Its temporary
harness and evidence remain under `.cache/logging-725/integrated-micro*` and
`.cache/logging-725/LoggingOverheadIntegratedProbeTests.swift`. It is not part
of the automatic suite. The Sentry row is a synthetic warning flood; ordinary
debug messages do not enter that handler. There is no basis here to weaken
actionable warning/error reporting.

## Admission and durability policy

- Ordinary file entries are admitted before queue submission, metadata-provider
  execution, string conversion of metadata, and JSON encoding. Swift-log message
  interpolation and caller-supplied metadata can already have run; this change
  does not make arbitrary producer work lazy.
- Each file writer allows at most 256 pending noncritical records, counting its
  running entry. This is a record-count bound, not a byte or latency guarantee.
  The tested 100-record burst fits with headroom. The cap is a bounded starting
  policy, not a measured universal optimum.
- Keep the existing burst of 50 and refill of one record per second per
  `(file, line)`. Admission is first-come; it does not promise fairness when many
  sites fill the aggregate cap. Each rejected site retains its count and source
  context even if none of its entries were accepted. Chart-state fairness is
  handled independently by the mapped store.
- Routine foreground and background file entries use the background-priority
  worker without waiting. Critical records still bypass admission and finish
  synchronously. Existing explicit lifecycle flushes remain in place. Routine
  asynchronous app logs remain best-effort crash evidence.
- OSLog and Sentry siblings are unchanged. File overload can omit a noncritical
  warning/error from that file; it does not suppress the other output handlers.
- Capture pending suppression counts with admission so later drops cannot be
  attached to an older queued entry. Restore unpersisted counts and refund the
  token after a failed append. A flush drains work submitted before its queue
  barrier and writes remaining suppression counts still held by the writer.
  A concurrent log call can pause after admission, holding a record and captured
  suppression count, then submit after the flush returns. Termination in that
  interval can lose this routine evidence. This narrow risk is accepted for
  best-effort diagnostics; completed log calls are already submitted, and
  critical calls still finish synchronously. Tests cover ordering, concurrent
  producers, failed writes, early metadata rejection, shared rate limits,
  rotation, and previous-session history.

The chart store from [#724](https://github.com/jubishop/podhaven/issues/724)
replaces this branch's provisional synchronous chart journal. There is no
remaining production caller for the provisional lazy-message overload, so it
was removed. Chart updates do not enter `FileLogHandler`.

## Playback evidence limits

The build-584 Sentry attachment described in #725 retains a remote load time of
3.472 seconds and a play-request-to-playing interval of 2.404 seconds. It does
not retain the complete automatic-transition start or detailed load phases.
Its chart snapshots begin after playing was observed. Retained event counts
cannot establish logging CPU cost or causal ordering for missing records.

The leading retained sites were defaults storage (nine records), widget reloads
(eight), database completion and playback-status changes (five each), followed
by view-state and player-observation sites (four each). These are volume
candidates, not a cost ranking. Removing their messages solely from these
counts would discard evidence without demonstrating a benefit.

The earlier cached AVPlayer comparison reported medians of 138.10 ms without
the added file sinks, 147.42 ms with synchronous sinks, and 135.78 ms with
asynchronous sinks. A later raw-log inspection found Apple `Fig` diagnostics
even though its result checker passed. Treat those figures as exploratory,
not diagnostic-free acceptance evidence.

The October 2 pilot replaced explicit near-end seeks with natural completion
and enabled the real audio session. It completed all 24 combinations of cached
or HTTPS media, active or background application-state flags, zero or two
competing synthetic downloads, and three file policies. It still emitted Apple
media-framework diagnostics and a CMTime rounding warning for the short audio
fixture, so the raw-log gate failed. No full repeated end-to-end matrix is
accepted. Changing an application-state flag also does not reproduce a locked
physical phone. Audio was muted; progress was not audible onset. Test capture,
stderr logging, and hosted progress rings remained common harness overhead.

## Integrated crash evidence

The controlled Simulator test on clean commit `d472944a` crashed immediately
after seven known final chart updates, then relaunched twice with chart and
general-log churn. Remote Sentry event `c9f50558df4e4cda97db3c9338f533ae`
delivered a 62,662-byte attachment containing 61 snapshots across eight
instances, all seven active final states and the terminal ring. The verifier
checked the prior-session identity, source attribution, values, geometry,
revision/sequence, retention limits, and byte bounds. Evidence is under
`.cache/sentry-charts-smoke/20b358c06f7f41b6b47aa44d92ef1629/`.

This verifies integration of the new logger with #724's automatic crash
evidence. The original Charts trap was not reproduced. No physical iPhone was
used. #724 owns its completed Sentry tracking closeout; this logging change
does not claim to fix that crash.
