---
name: podcast-detail-observation-storm
description: Active investigation (#293) of the PodcastDetail observation storm — observePodcastSeries/transition runaway. State 2026-05-20 — build-499 diagnostic run did NOT reproduce it; instrumentation (c45e2908) kept for another run. Sibling bug #296 in [[recommendation_engine_full_library_rescan]].
type: project
---

# PodcastDetail observation storm — investigation (#293)

Active investigation. Read this first when resuming.

## The bug

`Observatory.podcastSeriesDetail` (a GRDB `ValueObservation`) drives
`PodcastDetailViewModel.observePodcastSeries`, which calls `transition` on
every emission. Under the storm it emits ~178×/s → `transition` runs ~178×/s →
~533 log lines/s → the main actor is pegged and the whole app is unusable
(lists won't load, queueing dead) across all tabs. No crash, no error-level
event — every storm line is `.debug`, so nothing alerts.

Storm log signature — three `.debug` lines, each ~2,200× per ~12 s window:
- `startObservation` — "Observation already active; not starting observation"
- `observePodcastSeries` — "Updating observed series: …"
- `logStateTransition` — "transitioning state saved(…) → saved(…)" (same → same)

## History

- #274: original report. Fix shipped only plan items #1–#3 (the recommendation
  *scoring* coalescer — commit `0cc82c8c`, PR #275). Plan item #4, the
  observation storm itself, was deferred and never shipped.
- Recurred on **TestFlight build 498** (commit `967ddf79`, tag `v1.0b498`),
  which already contains the #274 fix. Sentry feedbacks `podhaven:7493496709`
  + `podhaven:7493497368` (2026-05-19), back-to-back.
- Tracked as **#293** (diagnose + fix). FileLogHandler perf tech-debt spun off
  as **#294**.
- **Build 499 diagnostic run (2026-05-20):** TestFlight build from commit
  `8a4aa613` (carries the `c45e2908` probes). Sentry feedbacks
  `podhaven:7495117741` + `podhaven:7495118557`. This run **did not reproduce
  #293** — the reporter never opened a `PodcastDetailView`. It surfaced a
  separate bug instead: #296 / [[recommendation_engine_full_library_rescan]].

## Established / ruled out

- **`.removeDuplicates()` is applied** — `Observatory.observe`
  (`Observatory.swift:317`) is
  `ValueObservation.tracking(block).removeDuplicates().values(in: repo.db)`. So
  a sustained ~178 emissions/s getting past it means genuinely-unequal
  consecutive values.
- **`currentTime` / tap-play hypothesis — DISPROVEN.** Reproduces freely
  on-device by *just opening a `PodcastDetailView` with nothing playing*.
- **Episode count alone is not the trigger** — a 2,000-episode podcast in an
  otherwise-empty Simulator DB did not storm.
- **Basic `PodcastSeriesDetail` `Equatable` is sound** — `PodcastSeriesDetailTests`
  (committed) passes: a fetched detail is reflexively equal and stable across
  re-fetch and an unrelated write. Gross `removeDuplicates` breakage unlikely.
- **Device-specific.** Does NOT reproduce in a Simulator Development build even
  with the real device DB loaded (978 MB — 171 podcasts, 96,037 episodes).
- **`WriteProbe` has NOT yet seen a storming session.** In the build-499 run
  (which did not storm) it showed a normal ~2.6 commits/s baseline. It still
  needs to run during an actual #293 storm to answer the open question below.

## The open question

The original 12.8 s feedback log shows **6,833 `ValueObservation` emissions vs
only ~2 DB writes**. Still unresolved which:

1. a real ~178-commits/s write storm on the observed region (`podcast` /
   `episode` / `episodeTag` / `podcastTag` / `episodeEmbedding`);
2. the observation layer emitting without DB writes;
3. an unstable `Equatable` (e.g. tied-pubDate episode ordering, tag-ID order)
   defeating `removeDuplicates`, so any steady background write storms it.

Needs a `WriteProbe` + emission-diff capture from a session that actually
opens a `PodcastDetailView` and storms. The build-499 run did not provide it.

## In-flight instrumentation — DO NOT revert yet

Commit **`c45e2908`** (`🔬 chore(diagnostics)…`) — temporary, three files;
present in build 499. **Keep it** until a TestFlight run reproduces the #293
storm — the build-499 run did not, so it has not yet done its job for #293.
After a storming run is captured: `git revert c45e2908`.

- `WriteProbe.swift` — a GRDB `TransactionObserver` (installed in
  `AppDB._onDisk`) logging committed-write rate, tables, and a sampled
  backtrace → names the writer, or shows there are none.
- `observePodcastSeries` emission-diff (probe 3b) — logs
  `podcastSeriesDetail emission diff:` = which `PodcastSeriesDetail` field
  differs between consecutive emissions. Did not fire in build 499 (no detail
  view opened).

Keepers (do NOT revert): `FileLogHandler` per-call-site rate-limit dedup
(`b7be5ebd`); `PodcastSeriesDetailTests` (`c94edefd`).

## Next step

1. TestFlight run from build 499 (or later, still carrying `c45e2908`):
   **open a storming `PodcastDetailView`** and let it run.
2. Settings → Debug → "Share PodHaven Logs" → `log.ndjson`.
3. Analyse with the `analyze-logs` `log_summary.py` script: `--sessions` →
   `--session N` → `--call-sites`. `WriteProbe` "DB commit" rate + sampled
   backtrace = the writer; `podcastSeriesDetail emission diff:` = the
   differing field. Together → the diagnosis.
4. Implement the #4 fix in #293; then `git revert c45e2908`.

## Key references

- `Observatory.observe` / `Observatory.podcastSeriesDetail` — `PodHaven/Database/Observatory.swift`.
- `observePodcastSeries`, `transition` — `PodHaven/Views/Podcasts/Models/PodcastDetailViewModel.swift`.
- `PodcastSeriesDetail` = `podcast` + `episodes: IdentifiedArrayOf<ListableEpisode>` + `tags`, synthesized `Equatable`. `ListableEpisode.databaseSelection` pulls `episodeEmbedding` into the tracked region via `EpisodeEmbedding.existsSelectable`.
- Device repro: open any `PodcastDetailView`, nothing playing.

## Related

- [[recommendation_engine_full_library_rescan]] — #296, the sibling bug found
  in the build-499 run: same architectural weakness (a SwiftUI observation
  triggering uncoalesced heavy work), different loop. Either alone pegs the app.
- [[recommendation_sort_prewarming]] — prewarming behaviour any fix must preserve.
- [[device_debug_builds_break_background_scheduling]] — no on-device debugging; TestFlight only.
- [[build_variants_dev_debug_release]] — dev/debug/release variants, data dirs, and why `log.ndjson` exists only on device Release builds.
