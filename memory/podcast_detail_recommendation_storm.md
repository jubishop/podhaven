---
name: podcast-detail-observation-storm
description: Investigation (#293) of the PodcastDetail observation storm. Root cause RESOLVED 2026-05-20 — real writes; Observatory.podcastSeriesDetail tracks too wide a region. WriteProbe promoted to a permanent enableWriteProbe debug toggle; emission-diff probe kept until #293 confirmed, removal tracked by #298.
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

Not turnkey: `EpisodeEmbedding.existsSelectable` lives in the **shared**
`ListableEpisode.databaseSelection` and feeds a stored `hasEmbedding` field —
narrowing needs a separate slim selection for the detail fetch, not a line
delete. And the catastrophic ~178/s rate was never captured with the probe, so
the `EmbeddingProcessor` attribution is unproven — verify the fix against the
original repro before closing. See the **#293 "Implementer handoff" comment**.

## In-flight instrumentation

Commit **`c45e2908`** (`🔬 chore(diagnostics)…`) added three diagnostic pieces,
present from build 499. Their fate has since diverged:

- `WriteProbe.swift` + its registration in `AppDB._onDisk` — **now
  permanent.** Promoted to a debug facility gated by the `enableWriteProbe`
  user setting (off by default, toggled live in the Settings Debug section).
  `WriteProbe` is registered on the DB once (`AppDB` passes it the setting's
  `Broadcast` via `init`); its `observes(eventsOfKind:)` returns the setting,
  which GRDB re-checks before every statement — so the toggle is live with no
  relaunch and the probe sees no per-row events while off. Do NOT revert.
- `observePodcastSeries` emission-diff probe in `PodcastDetailViewModel` —
  **still temporary.** It is the verification tool for the #293 fix (confirms
  the re-emissions stop). Keep until #293 is shipped and confirmed on a
  TestFlight build; removal tracked by **#298** — a targeted removal of the
  `emissionDiff` helper + its `.notice` call, NOT `git revert c45e2908` (that
  would tear out `WriteProbe` too).

Keepers (NOT part of `c45e2908`, do NOT revert): `FileLogHandler` per-call-site
rate-limit dedup (`b7be5ebd`); `PodcastSeriesDetailTests` (`c94edefd`).

## Next step

1. Implement the #4 fix (narrow `Observatory.podcastSeriesDetail`'s region).
2. Ship a TestFlight build; confirm via the emission-diff probe that
   re-emissions stop.
3. Then remove the emission-diff probe per #298.

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
