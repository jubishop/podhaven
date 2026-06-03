---
status: blocked
---

# Freshness Cadence Cache

Cache each podcast's auto-inferred `FreshnessCadence` in a stored
`inferredFreshnessCadence` column so recommendation scoring stops re-deriving it
from raw episode `pubDate`s on every observation fire.

## Blocked on #408

Do not start until **#408 ("Stop inferring evergreen freshness cadence from
episode recency")** is merged and closed. #408 removes the `dormantThresholdHours`
short-circuit from `FreshnessCadence.infer(from:now:)`, which makes inference a
**pure function of episode `pubDate`s** — no `now` dependency. That purity is the
unlock for this initiative: a cached value is then invalidated *only* by episode
changes, with no time-based staleness and no live read-time dormancy check. If we
cached before #408, the dormant→evergreen transition (driven by wall-clock, not
data) would silently rot the cache. Proceed only once #408 has landed.

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

### Open questions

- **Backfill.** Migrations use literals only (no model types / `infer`), so we
  can't backfill in the migration body. Options: leave the column nil and
  populate lazily at the next per-podcast refresh (resolution falls back to
  `.default` meanwhile), or run a one-time backfill pass on launch. Decide based
  on how jarring a transient `.default` window is.
- **Hook point.** Exactly where in the refresh path (RefreshManager /
  RefreshScheduler / episode-insert site) to trigger the per-podcast recompute.
- **Episode deletion.** Whether to recompute on deletion (rare) or ignore.
- **Settings UI.** Whether to surface the inferred value read-only (e.g. "Auto:
  Weekly") in `PodcastSettingsView`. Out of scope but worth a follow-up.

## Telemetry (gathering data before we proceed)

A `perf:` probe is in `resolveFreshnessCadences` to quantify the current cost
before committing to the cache. It logs at `.debug` from
`LogSubsystem.Database.recommendationRepo`:

```
perf: resolveFreshnessCadences took <total> — manual=<m> (<dur>) inferred=<i> from <n> pubDates (fetch <dur>, infer <dur>)
```

- Pull it from a device/TestFlight build (not simulator — file logging is
  device-only): export `log.ndjson` from Settings → Debug, or via the feedback
  form attachment. Then `grep 'perf: resolveFreshnessCadences'`.
- It fires from **both** consumers (observation and rebuild), so frequency in
  the log also shows how often the observation re-fires.
- **Decision gate:** if `fetch + infer` is negligible relative to fleet size,
  the cache is low priority. If it's significant and fires on every feed insert,
  proceed with the plan above.
</content>
