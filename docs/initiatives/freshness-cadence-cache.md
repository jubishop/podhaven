---
status: shipped
---

# Freshness Cadence Cache

Cache each podcast's auto-inferred `FreshnessCadence` in a stored
`inferredFreshnessCadence` column so recommendation scoring stops re-deriving it
from raw episode `pubDate`s on every observation fire.

## Unblocked by #408

This was gated on **#408 ("Stop inferring evergreen freshness cadence from
episode recency")**, now merged. #408 removed the `dormantThresholdHours`
short-circuit from `FreshnessCadence.infer`, making inference a **pure function
of episode `pubDate`s** — no `now` dependency. That purity is the unlock: a
cached value is invalidated *only* by episode changes, with no time-based
staleness and no live read-time dormancy check. Caching before #408 would have
let the dormant→evergreen transition (driven by wall-clock, not data) silently
rot the cache.

## Why

Per-episode scoring already does the cheap thing: `FreshnessSignal.compute` reads
the podcast's cadence from a precomputed `[Podcast.ID: FreshnessCadence]` map
(`context.freshnessCadences[candidate.podcastID] ?? .default`). The cost is in
*building* that map.

`RecommendationRepo.resolveFreshnessCadences` runs inside
`RecommendationRepo.scoringContextInputs`, which is the tracked region of the
GRDB observation `Observatory.scoringContextInputsWithoutPartialSignals()`.
Because the inference path issues a raw SQL query over `episode(podcastId,
pubDate)`, **any episode insert wakes that observation** and re-runs the
*entire fleet's* cadence resolution from scratch — every nil-cadence podcast,
up to `FreshnessCadence.inferenceMaxSamples` (100) most-recent pubDates each, a
fresh median per show. Feed refresh inserts episodes constantly (hourly shows
now refresh hourly), so this recompute fires on a steady drumbeat even though a
median gap is stable after ~5 samples. `ScoringContextInputs` is `Equatable`, so
`removeDuplicates()` suppresses *downstream* engine work when nothing changed,
but the SQL + medians still execute to produce the value being compared.

## Current behavior (baseline)

- `Podcast.freshnessCadence: FreshnessCadence?` — `nil` means "auto", non-nil is
  a user-set manual override (edited in `PodcastSettingsView`). Nullability *is*
  the manual/auto flag.
- `resolveFreshnessCadences` (`RecommendationRepo.swift`):
  1. Manual rows (`freshnessCadence != nil`) read straight into the map.
  2. nil-cadence podcasts inferred via a single windowed SQL query
     (`ROW_NUMBER() OVER (PARTITION BY podcastId ORDER BY pubDate DESC)`, capped
     at 100), streamed ordered by `podcastId` into per-podcast buckets, then
     `FreshnessCadence.infer` takes the median inter-episode gap and buckets it.
- Consumers: the observation above (passes an empty partial-signal fetcher), and
  the engine's debounced rebuild `allScoringContextInputs()`.

## Plan

1. Add `inferredFreshnessCadence: FreshnessCadence?` to `podcast` via the next
   migration (shipped migrations are immutable — add, never edit). Leave
   `freshnessCadence` as the manual override; never conflate the two.
2. Compute/update the inferred value at **feed-refresh time, scoped to the
   podcast(s) whose episodes actually changed** — recompute `infer(from:)` for
   that one show and write the column. No fleet sweep.
3. Resolution collapses to `freshnessCadence ?? inferredFreshnessCadence ??
   .default` — plain column reads. The windowed query + median leave the
   scoring/observation hot path entirely.
4. **Key win:** with cadence read from a column, `episode(pubDate)` drops out of
   the scoring observation's tracked region, so feed inserts stop waking the
   recommendation observation for cadence reasons.

### Open questions (resolved)

- **Backfill.** Done in the migration (v50). Migrations can't call `infer`, so
  the backfill bucket-medians the 100 most-recent pubDates per podcast in raw
  SQL with literal hour ceilings that mirror `FreshnessCadence.infer`. Podcasts
  with fewer than 3 episodes stay nil and resolve to the default, exactly as
  `infer` returns `.default` for sparse input; the live per-podcast recompute
  fills them in as episodes arrive.
- **Hook point.** `RecommendationRepo.updateInferredFreshnessCadence(_:podcastID:)`,
  called inside the repo's own write transactions — `insertSeries`,
  `updateSeriesFromFeed`, and `upsertPodcastEpisodes` — right after the episode
  rows land, scoped to the changed podcast(s). It writes only when the value
  changes, so a stable cadence produces no write (and no observation wake).
- **Episode deletion.** No partial-episode-deletion path exists; `deletePodcast`
  cascades via FK, removing the row and its cached cadence outright, so the
  podcast drops from the resolved map with no recompute. If pruning is added
  later it should call `updateInferredFreshnessCadence`.
- **Settings UI.** Still out of scope — a follow-up could surface the inferred
  value read-only (e.g. "Auto: Weekly") in `PodcastSettingsView`.

## Telemetry

The `perf:` probe that quantified the old per-fire cost was removed along with
the windowed scan it measured — `resolveFreshnessCadences` is now a plain
two-column read, so there is nothing left to time in the hot path.
</content>
