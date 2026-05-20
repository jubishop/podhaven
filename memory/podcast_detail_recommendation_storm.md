---
name: podcast-detail-observation-storm
description: Investigation (#293) of the PodcastDetail observation storm. Root cause RESOLVED 2026-05-20 — real writes; Observatory.podcastSeriesDetail tracks too wide a region. Diagnostic probes (c45e2908) kept until #293 + #296 fixes confirmed; revert tracked by #298.
type: project
---

# PodcastDetail observation storm — investigation (#293)

Root cause resolved; fix not yet shipped. Read this first when resuming.

## The bug

`Observatory.podcastSeriesDetail` (a GRDB `ValueObservation`) drives
`PodcastDetailViewModel.observePodcastSeries`, which calls `transition` on
every emission — a same-state `saved → saved` transition. When the observation
re-fires fast enough the main actor is pegged and the whole app is unusable
(lists won't load, queueing dead) across all tabs. No crash, no error-level
event — every storm line is `.debug`, so nothing alerts. Severity scales with
the writer's rate (see Root cause): ~178/s in the original incident, ~0.3/s in
the build-499 capture.

Storm log signature — three `.debug` lines per cycle:
- `startObservation` — "Observation already active; not starting observation"
- `observePodcastSeries` — "Updating observed series: …"
- `logStateTransition` — "transitioning state saved(…) → saved(…)" (same → same)

## History

- #274: original report. Fix shipped only plan items #1–#3 (the recommendation
  *scoring* coalescer — commit `0cc82c8c`, PR #275). Plan item #4, the
  observation storm itself, was deferred and never shipped.
- Recurred on **TestFlight build 498** (commit `967ddf79`, tag `v1.0b498`) at
  ~178 emissions/s. Sentry feedbacks `podhaven:7493496709` +
  `podhaven:7493497368` (2026-05-19).
- Tracked as **#293**. FileLogHandler perf tech-debt spun off as **#294**.
- **Build 499 diagnostic run (2026-05-20)** — TestFlight build from commit
  `8a4aa613` (carries the `c45e2908` probes):
  - Feedbacks `podhaven:7495117741` + `podhaven:7495118557` — did NOT open a
    detail view; surfaced a separate bug, #296 /
    [[recommendation_engine_full_library_rescan]].
  - Feedback `podhaven:7495203521` — a deliberate PodcastDetailView capture.
    The emission-diff probe fired and **resolved the root cause** (below).

## Root cause — RESOLVED (Case 1: real writes)

The build-499 emission-diff probe (`podcastSeriesDetail emission diff:`) names
the exact `PodcastSeriesDetail` field that differs between consecutive
emissions. Every emission was a *genuine* change — e.g. `episode 131531
content changed`, `podcast row changed`, `episode count 1 → 509`. So:

- `removeDuplicates()` works correctly — values genuinely differ (Case 2 out).
- `PodcastSeriesDetail` `Equatable` is sound (Case 3 out).
- It is **Case 1 — real writes**.

`Observatory.podcastSeriesDetail` tracks a very wide region: the `podcast` row
**plus every episode row plus every episode's `episodeEmbedding`**
(`ListableEpisode.databaseSelection` pulls `episodeEmbedding` in via
`EpisodeEmbedding.existsSelectable`). *Any* write touching *any* episode of the
open podcast re-fires the whole-detail observation → `observePodcastSeries` →
`transition`.

Build-499 capture: user opened Crime Junkie (podcast 244) while downloading ~5
of its episodes (each download = 4 row writes), subscribing, and a feed refresh
added 508 episodes → 24 re-emissions in ~105 s (mild). The original ~178/s
storm is the same path with a far denser writer on the open podcast — prime
suspect `EmbeddingProcessor` churning `episodeEmbedding` rows (batches of 64
`upsertEmbeddings` seen in the same log).

## Fix direction (plan-item #4)

- Narrow the tracked region: drop `episodeEmbedding` existence — and any
  per-episode column the detail view does not render — from
  `Observatory.podcastSeriesDetail`.
- And/or coalesce/debounce emissions. `removeDuplicates` cannot help; the data
  really changes.

## In-flight instrumentation — KEEP until #293 + #296 fixed and confirmed

Commit **`c45e2908`** (`🔬 chore(diagnostics)…`) — temporary, three files;
present in build 499. Per the maintainer: keep until #293 *and* #296 fixes are
shipped and verified on a TestFlight build — the emission-diff probe is the
verification tool (confirms the fix stops the re-emissions). Revert is tracked
by **#298** (`git revert c45e2908`), blocked by #293 + #296.

- `WriteProbe.swift` + its `install` call in `AppDB._onDisk` — a GRDB
  `TransactionObserver` logging commit rate, tables, sampled backtraces.
- `observePodcastSeries` emission-diff probe in `PodcastDetailViewModel`.

Keepers (NOT part of `c45e2908`, do NOT revert): `FileLogHandler` per-call-site
rate-limit dedup (`b7be5ebd`); `PodcastSeriesDetailTests` (`c94edefd`).

## Next step

1. Implement the #4 fix (narrow `Observatory.podcastSeriesDetail`'s region).
2. Ship a TestFlight build (still carrying `c45e2908`); confirm via the
   emission-diff probe that re-emissions stop.
3. Then revert `c45e2908` per #298.

Analyse logs with the `analyze-logs` `log_summary.py` script: `--sessions` →
`--session N` → `--call-sites`.

## Key references

- `Observatory.observe` / `Observatory.podcastSeriesDetail` — `PodHaven/Database/Observatory.swift` (`observe` = `ValueObservation.tracking(block).removeDuplicates().values(in:)`).
- `observePodcastSeries`, `transition` — `PodHaven/Views/Podcasts/Models/PodcastDetailViewModel.swift`.
- `PodcastSeriesDetail` = `podcast` + `episodes: IdentifiedArrayOf<ListableEpisode>` + `tags`, synthesized `Equatable`.

## Related

- [[recommendation_engine_full_library_rescan]] — #296, the sibling bug: same
  architectural weakness (a SwiftUI observation triggering uncoalesced heavy
  work), different loop. Either alone pegs the app.
- #297 — `EmbeddingProcessor` FK-on-delete race, found in the same build-499 log.
- [[recommendation_sort_prewarming]] — prewarming behaviour any fix must preserve.
- [[device_debug_builds_break_background_scheduling]] — no on-device debugging; TestFlight only.
- [[build_variants_dev_debug_release]] — why `log.ndjson` exists only on device Release builds.
